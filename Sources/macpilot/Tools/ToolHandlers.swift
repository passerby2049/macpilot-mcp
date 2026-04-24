import CoreGraphics
import Foundation
import MCP

typealias ToolResult = (content: [Tool.Content], isError: Bool)

private func txt(_ s: String) -> Tool.Content {
    .text(text: s, annotations: nil, _meta: nil)
}

private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}()

struct ToolHandlers: @unchecked Sendable {
    let screen: ScreenService
    let pointer: PointerService
    let keyboard: KeyboardService
    let clipboard: ClipboardService
    let window: WindowService
    let apps: ApplicationService

    // MARK: screen_context

    func screenContext(args: [String: Value]?) async throws -> ToolResult {
        let displayID = args?["display_id"]?.intValue.map { CGDirectDisplayID($0) }
        let ctx = try await screen.captureContext(displayID: displayID)
        struct Meta: Codable {
            let display: ScreenService.DisplayInfo
            let cursorLocation: CGPoint
            let activeApp: ScreenService.ActiveApp?
        }
        let meta = Meta(display: ctx.display, cursorLocation: ctx.cursorLocation, activeApp: ctx.activeApp)
        let json = String(data: try encoder.encode(meta), encoding: .utf8) ?? "{}"
        return ([
            .image(data: ctx.screenshotJpegBase64, mimeType: "image/jpeg", annotations: nil, _meta: nil),
            txt(json),
        ], false)
    }

    // MARK: display_list

    func displayList(args: [String: Value]?) throws -> ToolResult {
        let list = screen.listDisplays()
        let json = String(data: try encoder.encode(list), encoding: .utf8) ?? "[]"
        return ([txt(json)], false)
    }

    // MARK: pointer

    func pointerSequence(args: [String: Value]?) async throws -> ToolResult {
        guard case .array(let events)? = args?["events"] else {
            return ([txt("`events` array is required")], true)
        }
        for (i, ev) in events.enumerated() {
            guard case .object(let dict) = ev else {
                return ([txt("event[\(i)] must be an object")], true)
            }
            guard let type = dict["type"]?.stringValue else {
                return ([txt("event[\(i)] missing `type`")], true)
            }
            switch type {
            case "move":
                guard let x = dict["x"]?.doubleValue, let y = dict["y"]?.doubleValue else {
                    return ([txt("move[\(i)] needs x,y")], true)
                }
                pointer.move(to: CGPoint(x: x, y: y))
            case "click":
                guard let x = dict["x"]?.doubleValue, let y = dict["y"]?.doubleValue else {
                    return ([txt("click[\(i)] needs x,y")], true)
                }
                let button = parseButton(dict["button"]?.stringValue)
                let count = dict["count"]?.intValue ?? 1
                try pointer.click(at: CGPoint(x: x, y: y), button: button, count: count)
            case "down":
                guard let x = dict["x"]?.doubleValue, let y = dict["y"]?.doubleValue else {
                    return ([txt("down[\(i)] needs x,y")], true)
                }
                try pointer.down(at: CGPoint(x: x, y: y), button: parseButton(dict["button"]?.stringValue))
            case "up":
                guard let x = dict["x"]?.doubleValue, let y = dict["y"]?.doubleValue else {
                    return ([txt("up[\(i)] needs x,y")], true)
                }
                try pointer.up(at: CGPoint(x: x, y: y), button: parseButton(dict["button"]?.stringValue))
            case "drag":
                guard let fx = dict["from_x"]?.doubleValue, let fy = dict["from_y"]?.doubleValue,
                      let tx = dict["to_x"]?.doubleValue,   let ty = dict["to_y"]?.doubleValue else {
                    return ([txt("drag[\(i)] needs from_x,from_y,to_x,to_y")], true)
                }
                try pointer.drag(from: CGPoint(x: fx, y: fy), to: CGPoint(x: tx, y: ty),
                                 button: parseButton(dict["button"]?.stringValue))
            case "scroll":
                guard let x = dict["x"]?.doubleValue, let y = dict["y"]?.doubleValue else {
                    return ([txt("scroll[\(i)] needs x,y")], true)
                }
                let dx = dict["dx"]?.intValue ?? 0
                let dy = dict["dy"]?.intValue ?? -120
                try pointer.scroll(at: CGPoint(x: x, y: y), dx: dx, dy: dy)
            default:
                return ([txt("event[\(i)] unknown type: \(type)")], true)
            }
        }
        return ([txt("OK — posted \(events.count) events")], false)
    }

    // MARK: keyboard

    func keyboardType(args: [String: Value]?) throws -> ToolResult {
        guard let text = args?["text"]?.stringValue else {
            return ([txt("`text` is required")], true)
        }
        try keyboard.type(text)
        return ([txt("Typed \(text.count) characters")], false)
    }

    func keyboardPress(args: [String: Value]?) throws -> ToolResult {
        guard let combo = args?["combo"]?.stringValue else {
            return ([txt("`combo` is required")], true)
        }
        try keyboard.press(combo)
        return ([txt("Pressed \(combo)")], false)
    }

    // MARK: clipboard

    func clipboardGet(args: [String: Value]?) throws -> ToolResult {
        return ([txt(clipboard.get())], false)
    }

    func clipboardSet(args: [String: Value]?) throws -> ToolResult {
        guard let text = args?["text"]?.stringValue else {
            return ([txt("`text` is required")], true)
        }
        clipboard.set(text)
        return ([txt("OK — \(text.count) chars")], false)
    }

    // MARK: menu_invoke

    func menuInvoke(args: [String: Value]?) throws -> ToolResult {
        guard case .array(let pathVals)? = args?["path"] else {
            return ([txt("`path` array is required")], true)
        }
        let path = pathVals.compactMap { $0.stringValue }
        if path.isEmpty {
            return ([txt("`path` must contain at least one segment")], true)
        }
        try window.invokeMenu(appName: args?["app_name"]?.stringValue, path: path)
        return ([txt("Invoked menu: " + path.joined(separator: " > "))], false)
    }

    // MARK: window_focus

    func windowFocus(args: [String: Value]?) throws -> ToolResult {
        guard let appName = args?["app_name"]?.stringValue else {
            return ([txt("`app_name` is required")], true)
        }
        try window.focusWindow(
            appName: appName,
            windowTitleContains: args?["window_title_contains"]?.stringValue
        )
        return ([txt("Focused \(appName)")], false)
    }

    // MARK: wait

    func wait(args: [String: Value]?) async throws -> ToolResult {
        guard let ms = args?["ms"]?.intValue, ms >= 0 else {
            return ([txt("`ms` (non-negative integer) is required")], true)
        }
        try await Task.sleep(for: .milliseconds(ms))
        return ([txt("Slept \(ms)ms")], false)
    }

    func waitForElement(args: [String: Value]?) async throws -> ToolResult {
        let timeout = args?["timeout_ms"]?.intValue ?? 5000
        let found = await window.waitForElement(
            appName: args?["app_name"]?.stringValue,
            role: args?["role"]?.stringValue,
            label: args?["label"]?.stringValue,
            title: args?["title"]?.stringValue,
            timeoutMs: timeout
        )
        return ([txt("{\"found\": \(found)}")], false)
    }

    // MARK: applications

    func applicationsList(args: [String: Value]?) throws -> ToolResult {
        let list = apps.list()
        let json = String(data: try encoder.encode(list), encoding: .utf8) ?? "[]"
        return ([txt(json)], false)
    }

    func applicationsOpen(args: [String: Value]?) async throws -> ToolResult {
        try await apps.open(
            bundleIdentifier: args?["bundle_identifier"]?.stringValue,
            name: args?["name"]?.stringValue,
            path: args?["path"]?.stringValue
        )
        return ([txt("OK")], false)
    }

    func applicationsTerminate(args: [String: Value]?) throws -> ToolResult {
        try apps.terminate(
            bundleIdentifier: args?["bundle_identifier"]?.stringValue,
            name: args?["name"]?.stringValue,
            path: args?["path"]?.stringValue,
            force: args?["force"]?.boolValue ?? false
        )
        return ([txt("OK")], false)
    }

    // MARK: helpers

    private func parseButton(_ s: String?) -> PointerService.Button {
        switch s?.lowercased() {
        case "right":  return .right
        case "middle": return .middle
        default:       return .left
        }
    }
}

// MARK: - Value helpers

extension Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i)    = self { return Double(i) }
        return nil
    }
    var intValue: Int? {
        if case .int(let i)    = self { return i }
        if case .double(let d) = self { return Int(d) }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}
