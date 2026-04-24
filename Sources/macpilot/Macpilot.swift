import ApplicationServices
import Foundation
import MCP

@main
struct Macpilot {
    static func main() async throws {
        // Trigger AX permission prompt at startup.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        let server = Server(
            name: "macpilot",
            version: "0.3.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        let screen = ScreenService()
        let handlers = ToolHandlers(
            screen: screen,
            pointer: PointerService(),
            keyboard: KeyboardService(),
            clipboard: ClipboardService(),
            window: WindowService(screen: screen),
            apps: ApplicationService()
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: Tool.allTools)
        }

        await server.withMethodHandler(CallTool.self) { [handlers] params in
            do {
                let (content, isError) = try await dispatch(
                    name: params.name, args: params.arguments, handlers: handlers
                )
                return CallTool.Result(content: content, isError: isError)
            } catch {
                return CallTool.Result(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

private func dispatch(
    name: String, args: [String: Value]?, handlers: ToolHandlers
) async throws -> ToolResult {
    switch name {
    case "screen_context":          return try await handlers.screenContext(args: args)
    case "display_list":            return try handlers.displayList(args: args)
    case "pointer":                 return try await handlers.pointerSequence(args: args)
    case "keyboard_type":           return try handlers.keyboardType(args: args)
    case "keyboard_press":          return try handlers.keyboardPress(args: args)
    case "clipboard_get":           return try handlers.clipboardGet(args: args)
    case "clipboard_set":           return try handlers.clipboardSet(args: args)
    case "menu_invoke":             return try handlers.menuInvoke(args: args)
    case "window_focus":            return try handlers.windowFocus(args: args)
    case "wait":                    return try await handlers.wait(args: args)
    case "wait_for_element":        return try await handlers.waitForElement(args: args)
    case "applications_list":       return try handlers.applicationsList(args: args)
    case "applications_open":       return try await handlers.applicationsOpen(args: args)
    case "applications_terminate":  return try handlers.applicationsTerminate(args: args)
    default:
        return ([.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)], true)
    }
}
