import AppKit
import ApplicationServices
import Foundation

/// AX-driven menu invocation, window focusing, and polling waits.
/// Uses coordinate-free AX actions (kAXPressAction, kAXRaiseAction) which work reliably
/// on macOS 26 unified toolbars and menu bars.
final class WindowService {
    let screen: ScreenService

    init(screen: ScreenService) {
        self.screen = screen
    }

    // MARK: - Menu invoke

    /// Invoke a menu by path, e.g. ["File", "New Story"] or ["Window", "Minimize"].
    /// Finds the AXMenuBar of the named app (or frontmost) and walks the path.
    func invokeMenu(appName: String?, path: [String]) throws {
        guard !path.isEmpty else {
            throw AutomationError.invalidInput("menu path must not be empty")
        }
        let pid: pid_t
        if let appName {
            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                ($0.localizedName ?? "").localizedCaseInsensitiveContains(appName)
                    || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(appName)
            }) else { throw AutomationError.appNotFound(appName) }
            pid = app.processIdentifier
        } else {
            guard let app = NSWorkspace.shared.frontmostApplication else {
                throw AutomationError.noFrontmostApp
            }
            pid = app.processIdentifier
        }
        let root = AXUIElementCreateApplication(pid)
        guard let menuBar = screen.axAttribute(root, kAXMenuBarAttribute) else {
            throw AutomationError.invalidInput("app has no menu bar")
        }
        let menuBarEl = menuBar as! AXUIElement

        // Walk each segment: find child whose title matches (case-insensitive).
        var current: AXUIElement = menuBarEl
        for (index, segment) in path.enumerated() {
            guard let match = child(of: current, titled: segment) else {
                throw AutomationError.invalidInput("menu segment not found: \(segment)")
            }
            let isLast = index == path.count - 1
            if isLast {
                AXUIElementPerformAction(match, kAXPressAction as CFString)
                return
            }
            // Non-leaf: the child itself is a menu bar item or submenu — descend into its AXMenu child.
            if let submenu = screen.axAttribute(match, kAXChildrenAttribute) as? [AXUIElement],
               let menu = submenu.first(where: { screen.axString($0, kAXRoleAttribute) == "AXMenu" }) {
                current = menu
            } else {
                current = match
            }
        }
    }

    private func child(of parent: AXUIElement, titled title: String) -> AXUIElement? {
        guard let kids = screen.axAttribute(parent, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        return kids.first { el in
            if let t = screen.axString(el, kAXTitleAttribute),
               t.localizedCaseInsensitiveCompare(title) == .orderedSame { return true }
            return false
        }
    }

    // MARK: - Window focus

    /// Bring the specified app (and optionally a specific window by title substring) to front.
    func focusWindow(appName: String, windowTitleContains: String?) throws {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains(appName)
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(appName)
        }) else { throw AutomationError.appNotFound(appName) }

        app.activate(options: [.activateAllWindows])

        if let titleSub = windowTitleContains {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            if let windows = screen.axAttribute(root, kAXWindowsAttribute) as? [AXUIElement],
               let target = windows.first(where: {
                   screen.axString($0, kAXTitleAttribute)?
                       .localizedCaseInsensitiveContains(titleSub) == true
               }) {
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            }
        }
    }

    // MARK: - Wait for element

    /// Poll the AX tree until an element matching role/label/title appears or timeout expires.
    /// Returns true if found, false if timed out.
    func waitForElement(
        appName: String?, role: String?, label: String?, title: String?,
        timeoutMs: Int
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if screen.findElement(appName: appName, role: role, label: label, title: title) != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }
}
