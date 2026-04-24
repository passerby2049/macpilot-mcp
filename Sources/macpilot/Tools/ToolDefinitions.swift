import MCP

extension Tool {
    static let allTools: [Tool] = [
        screenContext,
        displayList,
        pointer,
        keyboardType,
        keyboardPress,
        clipboardGet,
        clipboardSet,
        menuInvoke,
        windowFocus,
        wait,
        waitForElement,
        applicationsList,
        applicationsOpen,
        applicationsTerminate,
    ]

    static let screenContext = Tool(
        name: "screen_context",
        description: """
        Capture a display (JPEG, base64) AND the frontmost app's interactive accessibility \
        elements (buttons, text fields, menu items) clipped to that display's bounds. \
        Returns cursor location and active app metadata. Pure-container roles (AXRow/AXCell) \
        and decorative images are filtered out.
        Defaults to the display containing the frontmost window. Use `display_list` to enumerate \
        displays and pass `display_id` to target a specific one (multi-monitor setups).
        All coordinates are Quartz global (top-left origin of primary display), matching `pointer`.
        """,
        inputSchema: schema(properties: [
            "display_id": prop("integer", "CGDirectDisplayID. Omit to auto-pick the frontmost display."),
        ])
    )

    static let displayList = Tool(
        name: "display_list",
        description: "Enumerate all connected displays with their CGDirectDisplayID, bounds (Quartz global), main/builtin flags, and HiDPI scale factor.",
        inputSchema: schema(properties: [:])
    )

    static let pointer = Tool(
        name: "pointer",
        description: """
        Execute a sequence of pointer events. Coordinates are Quartz (top-left origin, same as `screen_context` frames). Each event is one of:
          {"type":"move","x":N,"y":N}
          {"type":"click","x":N,"y":N,"button":"left|right|middle","count":1}
          {"type":"down","x":N,"y":N,"button":"left|right|middle"}
          {"type":"up","x":N,"y":N,"button":"left|right|middle"}
          {"type":"drag","from_x":N,"from_y":N,"to_x":N,"to_y":N,"button":"left"}
          {"type":"scroll","x":N,"y":N,"dx":0,"dy":-120}
        """,
        inputSchema: schema(
            properties: [
                "events": .object([
                    "type": .string("array"),
                    "description": .string("Sequence of pointer events"),
                    "items": .object(["type": .string("object")]),
                ]),
            ],
            required: ["events"]
        )
    )

    static let keyboardType = Tool(
        name: "keyboard_type",
        description: "Type Unicode text into the focused field. Batched — fast even for long URLs. For very long pastes, use clipboard_set + keyboard_press(cmd+v) instead.",
        inputSchema: schema(
            properties: ["text": prop("string", "Text to type")],
            required: ["text"]
        )
    )

    static let keyboardPress = Tool(
        name: "keyboard_press",
        description: """
        Press a key or key combo: "return", "escape", "tab", "cmd+n", "cmd+shift+z", "cmd+c", \
        "cmd+v", "cmd+w", "cmd+q", arrow keys ("left"/"right"/"up"/"down"), function keys (f1–f12).
        """,
        inputSchema: schema(
            properties: ["combo": prop("string", "Key or combo, e.g. \"cmd+n\"")],
            required: ["combo"]
        )
    )

    static let clipboardGet = Tool(
        name: "clipboard_get",
        description: "Read the current clipboard string. Empty string if clipboard has no text.",
        inputSchema: schema(properties: [:])
    )

    static let clipboardSet = Tool(
        name: "clipboard_set",
        description: "Write a string to the clipboard. Use with keyboard_press(cmd+v) for fast paste of URLs and long text.",
        inputSchema: schema(
            properties: ["text": prop("string", "Text to place on the clipboard")],
            required: ["text"]
        )
    )

    static let menuInvoke = Tool(
        name: "menu_invoke",
        description: """
        Invoke a menu bar item by path — reliable for features only exposed via the menu bar. \
        Uses AX press action directly (no coordinate math). Example: \
        {"app_name":"ListenWise","path":["File","New from link"]}. \
        Path segments match case-insensitively against AXTitle.
        """,
        inputSchema: schema(
            properties: [
                "app_name": prop("string", "App name (optional, defaults to frontmost)"),
                "path": .object([
                    "type": .string("array"),
                    "description": .string("Menu path, e.g. [\"File\", \"New\"]"),
                    "items": .object(["type": .string("string")]),
                ]),
            ],
            required: ["path"]
        )
    )

    static let windowFocus = Tool(
        name: "window_focus",
        description: "Activate an app and (optionally) raise a specific window by title substring. Use this to switch to an app without clicking.",
        inputSchema: schema(
            properties: [
                "app_name": prop("string", "App name or bundle id substring"),
                "window_title_contains": prop("string", "Optional: match a specific window's title"),
            ],
            required: ["app_name"]
        )
    )

    static let wait = Tool(
        name: "wait",
        description: "Sleep for the given number of milliseconds. Use sparingly — prefer wait_for_element.",
        inputSchema: schema(
            properties: ["ms": prop("integer", "Milliseconds to sleep")],
            required: ["ms"]
        )
    )

    static let waitForElement = Tool(
        name: "wait_for_element",
        description: "Poll the accessibility tree until an element matching role/label/title appears, or timeout expires. Returns {found: bool}.",
        inputSchema: schema(properties: [
            "app_name": prop("string", "App (defaults to frontmost)"),
            "role": prop("string", "AX role, e.g. \"AXButton\""),
            "label": prop("string", "Label substring, case-insensitive"),
            "title": prop("string", "Title substring, case-insensitive"),
            "timeout_ms": prop("integer", "Max wait in ms (default 5000)"),
        ])
    )

    static let applicationsList = Tool(
        name: "applications_list",
        description: "List running user-facing applications with pid, name, bundle id, and path.",
        inputSchema: schema(properties: [:])
    )

    static let applicationsOpen = Tool(
        name: "applications_open",
        description: "Open or focus an app. Provide at least one of: bundle_identifier, name, path.",
        inputSchema: schema(properties: [
            "bundle_identifier": prop("string", "e.g. \"com.apple.Safari\""),
            "name": prop("string", "App display name"),
            "path": prop("string", "Absolute path to .app bundle"),
        ])
    )

    static let applicationsTerminate = Tool(
        name: "applications_terminate",
        description: "Terminate an app. Provide at least one of: bundle_identifier, name, path. Use force=true for force-quit.",
        inputSchema: schema(properties: [
            "bundle_identifier": prop("string", ""),
            "name": prop("string", ""),
            "path": prop("string", ""),
            "force": prop("boolean", "Force quit (default false)"),
        ])
    )
}

// MARK: - Helpers

private func prop(_ type: String, _ description: String) -> Value {
    if description.isEmpty {
        return .object(["type": .string(type)])
    }
    return .object(["type": .string(type), "description": .string(description)])
}

private func schema(properties: [String: Value], required: [String] = []) -> Value {
    var obj: [String: Value] = [
        "type": .string("object"),
        "properties": .object(properties),
    ]
    if !required.isEmpty {
        obj["required"] = .array(required.map { .string($0) })
    }
    return .object(obj)
}
