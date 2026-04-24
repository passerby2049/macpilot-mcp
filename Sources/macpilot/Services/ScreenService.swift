import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Captures a chosen display and walks the frontmost app's AX tree.
/// All coordinates are Quartz global (top-left origin of primary display), matching CGEvent and AX.
final class ScreenService {

    /// Roles we consider worth surfacing to the caller. Pure containers (AXRow/AXCell) and
    /// decorative images are excluded — they bloat output without being clickable.
    static let interactiveRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox",
        "AXRadioButton", "AXPopUpButton", "AXComboBox", "AXSlider",
        "AXIncrementor", "AXColorWell", "AXMenuItem", "AXMenuButton",
        "AXMenuBarItem", "AXDisclosureTriangle", "AXSearchField",
        "AXSecureTextField", "AXToolbarButton",
    ]

    static let maxDepth = 12
    static let maxElements = 100

    // MARK: - Public types

    struct DisplayInfo: Codable {
        let displayID: UInt32
        let bounds: CGRect
        let isMain: Bool
        let isBuiltIn: Bool
        let scaleFactor: Double
    }

    struct ScreenContext: Codable {
        let screenshotJpegBase64: String
        let display: DisplayInfo
        let cursorLocation: CGPoint
        let activeApp: ActiveApp?
    }

    struct ActiveApp: Codable {
        let name: String?
        let bundleIdentifier: String?
        let processId: pid_t
        let windowTitle: String?
        let windowFrame: CGRect?
        let interactiveElements: [AXElement]
    }

    struct AXElement: Codable {
        let role: String
        let title: String?
        let label: String?
        let value: String?
        let identifier: String?
        let frame: CGRect
        let enabled: Bool?
        let focused: Bool?
    }

    // MARK: - Displays

    func listDisplays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(num.uint32Value)
            return DisplayInfo(
                displayID: id,
                bounds: CGDisplayBounds(id),
                isMain: CGDisplayIsMain(id) != 0,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                scaleFactor: Double(screen.backingScaleFactor)
            )
        }
    }

    // MARK: - Screen context

    func captureContext(displayID requestedID: CGDirectDisplayID?) async throws -> ScreenContext {
        let targetID = requestedID ?? preferredDisplay()
        let bounds = CGDisplayBounds(targetID)
        let (jpeg, displayInfo) = try await captureDisplay(displayID: targetID)
        let cursor = cursorLocationQuartz()
        let active = try? activeAppContext(clippingTo: bounds)
        return ScreenContext(
            screenshotJpegBase64: jpeg,
            display: displayInfo,
            cursorLocation: cursor,
            activeApp: active
        )
    }

    /// The display containing the frontmost app's key window, or main if none.
    private func preferredDisplay() -> CGDirectDisplayID {
        if let nsApp = NSWorkspace.shared.frontmostApplication {
            let appEl = AXUIElementCreateApplication(nsApp.processIdentifier)
            if let windows = axAttribute(appEl, kAXWindowsAttribute) as? [AXUIElement],
               let first = windows.first,
               let frame = axFrame(first) {
                let center = CGPoint(x: frame.midX, y: frame.midY)
                for screen in NSScreen.screens {
                    guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                    let id = CGDirectDisplayID(num.uint32Value)
                    if CGDisplayBounds(id).contains(center) { return id }
                }
            }
        }
        return CGMainDisplayID()
    }

    // MARK: - Capture

    private func captureDisplay(displayID: CGDirectDisplayID) async throws -> (String, DisplayInfo) {
        guard CGPreflightScreenCaptureAccess() else {
            throw AutomationError.noScreenCapturePermission
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw AutomationError.noDisplayFound
        }
        let bounds = CGDisplayBounds(displayID)
        let config = SCStreamConfiguration()
        config.width = Int(bounds.width)
        config.height = Int(bounds.height)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let scale: Double
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            scale = Double(mode.pixelWidth) / Double(mode.width)
        } else {
            scale = 1
        }

        let info = DisplayInfo(
            displayID: displayID,
            bounds: bounds,
            isMain: CGDisplayIsMain(displayID) != 0,
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
            scaleFactor: scale
        )
        return (encodeJPEG(image), info)
    }

    private func encodeJPEG(_ image: CGImage) -> String {
        let maxBytes = 3 * 1024 * 1024
        var quality: CGFloat = 0.8
        var current = image
        for _ in 0..<10 {
            if let data = jpegData(current, quality: quality), data.count <= maxBytes {
                return data.base64EncodedString()
            }
            quality = max(0.3, quality - 0.1)
        }
        if let scaled = scale(current, by: 0.6) {
            current = scaled
            for _ in 0..<5 {
                if let data = jpegData(current, quality: quality), data.count <= maxBytes {
                    return data.base64EncodedString()
                }
                quality = max(0.3, quality - 0.1)
            }
        }
        return jpegData(current, quality: 0.4)?.base64EncodedString() ?? ""
    }

    private func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        NSBitmapImageRep(cgImage: image)
            .representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    private func scale(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let w = Int(CGFloat(image.width) * factor)
        let h = Int(CGFloat(image.height) * factor)
        guard let colorSpace = image.colorSpace,
              let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0, space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - AX collection

    private func activeAppContext(clippingTo bounds: CGRect) throws -> ActiveApp {
        guard let nsApp = NSWorkspace.shared.frontmostApplication else {
            throw AutomationError.noFrontmostApp
        }
        let pid = nsApp.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)

        var windowTitle: String?
        var windowFrame: CGRect?
        var elements: [AXElement] = []

        if let windows = axAttribute(appEl, kAXWindowsAttribute) as? [AXUIElement],
           let window = windows.first {
            windowTitle = axString(window, kAXTitleAttribute)
            windowFrame = axFrame(window)
            var count = 0
            collectInteractive(window, depth: 0, count: &count, clipBounds: bounds, into: &elements)
        }

        return ActiveApp(
            name: nsApp.localizedName,
            bundleIdentifier: nsApp.bundleIdentifier,
            processId: pid,
            windowTitle: windowTitle,
            windowFrame: windowFrame,
            interactiveElements: elements
        )
    }

    private func collectInteractive(
        _ el: AXUIElement, depth: Int, count: inout Int, clipBounds: CGRect,
        into out: inout [AXElement]
    ) {
        guard depth < Self.maxDepth, count < Self.maxElements else { return }

        let role = axString(el, kAXRoleAttribute) ?? ""
        if Self.interactiveRoles.contains(role), let frame = axFrame(el), clipBounds.intersects(frame) {
            let title = axString(el, kAXTitleAttribute)
            let label = axString(el, kAXDescriptionAttribute)
            let value = axString(el, kAXValueAttribute)
            let identifier = axString(el, kAXIdentifierAttribute)
            // Keep only elements that carry signal — something to match on.
            if title != nil || label != nil || identifier != nil
                || role == "AXTextField" || role == "AXTextArea"
                || role == "AXSearchField" || role == "AXSecureTextField"
                || role == "AXSlider" {
                out.append(AXElement(
                    role: role, title: title, label: label, value: value,
                    identifier: identifier, frame: frame,
                    enabled: axBool(el, kAXEnabledAttribute),
                    focused: axBool(el, kAXFocusedAttribute)
                ))
                count += 1
            }
        }
        if let children = axAttribute(el, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                if count >= Self.maxElements { break }
                collectInteractive(child, depth: depth + 1, count: &count, clipBounds: clipBounds, into: &out)
            }
        }
    }

    // MARK: - Cursor

    private func cursorLocationQuartz() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        let h = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: cocoa.x, y: h - cocoa.y)
    }

    // MARK: - AX helpers (raw CF)

    func axAttribute(_ el: AXUIElement, _ attr: String) -> AnyObject? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &val) == .success else {
            return nil
        }
        return val
    }

    func axString(_ el: AXUIElement, _ attr: String) -> String? {
        guard let s = axAttribute(el, attr) as? String, !s.isEmpty else { return nil }
        return s
    }

    func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
        axAttribute(el, attr) as? Bool
    }

    func axFrame(_ el: AXUIElement) -> CGRect? {
        guard let posRef = axAttribute(el, kAXPositionAttribute),
              let sizeRef = axAttribute(el, kAXSizeAttribute),
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    // MARK: - Shared: find element by criteria

    /// Search the frontmost (or named) app's AX tree for an element matching role/label/title.
    /// Used by wait_for_element, menu_invoke.
    func findElement(
        appName: String?,
        role: String?, label: String?, title: String?,
        identifier: String? = nil
    ) -> AXUIElement? {
        let pid: pid_t
        if let appName {
            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                ($0.localizedName ?? "").localizedCaseInsensitiveContains(appName)
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(appName)
            }) else { return nil }
            pid = app.processIdentifier
        } else {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            pid = app.processIdentifier
        }
        let root = AXUIElementCreateApplication(pid)
        return findMatch(root, role: role, label: label, title: title, identifier: identifier, depth: 0)
    }

    private func findMatch(
        _ el: AXUIElement,
        role: String?, label: String?, title: String?, identifier: String?,
        depth: Int
    ) -> AXUIElement? {
        guard depth < Self.maxDepth else { return nil }
        let elRole = axString(el, kAXRoleAttribute)
        let elLabel = axString(el, kAXDescriptionAttribute)
        let elTitle = axString(el, kAXTitleAttribute)
        let elIdent = axString(el, kAXIdentifierAttribute)

        let roleOK  = role.map  { elRole == $0 } ?? true
        let labelOK = label.map { elLabel?.localizedCaseInsensitiveContains($0) == true } ?? true
        let titleOK = title.map { elTitle?.localizedCaseInsensitiveContains($0) == true } ?? true
        let identOK = identifier.map { elIdent == $0 } ?? true
        if roleOK && labelOK && titleOK && identOK { return el }

        if let children = axAttribute(el, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                if let found = findMatch(child, role: role, label: label, title: title, identifier: identifier, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }
}
