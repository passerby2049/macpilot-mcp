# macpilot

An MCP server that lets an LLM drive macOS apps — screenshot a display, read the accessibility tree, click, type, invoke menu items, and manage windows. Built for use with Claude Code as a general-purpose "computer use" tool on macOS.

Named to pair with [simpilot](https://github.com/passerby2049/simpilot) (iOS): `simpilot` flies the simulator, `macpilot` flies the Mac.

## Demo

Claude driving macOS through macpilot — opening ListenWise, navigating into a podcast subscription, and importing an episode end-to-end.

https://github.com/user-attachments/assets/7f627435-4851-4290-a415-7d87d96fb5e1

> **Credit.** Design inspired by [Lakr233/ComputerUse](https://github.com/Lakr233/ComputerUse), an excellent standalone Mac agent. Our screenshot pipeline (always `SCContentFilter(display:)`, never per-window — the difference between "works" and "SkyLight abort on sheet transitions"), the JPEG-with-quality-fallback encoder, the filtered interactive-element collector, and the Cocoa/Quartz coordinate hygiene all borrow directly from their approach. Ours is a small MCP wrapper around a similar core. Go read theirs.

## Requirements

- macOS 14+ (developed against macOS 26)
- Swift 6.0 toolchain
- **Accessibility** permission — System Settings → Privacy & Security → Accessibility
- **Screen Recording** permission — System Settings → Privacy & Security → Screen Recording

On first launch the server triggers the AX prompt. Screen Recording is lazy — you'll be prompted the first time `screen_context` runs.

## Build

```bash
swift build -c release
```

Binary lands at `.build/release/macpilot`.

## Claude Code setup

Edit `~/.claude.json`, adding the server under `mcpServers`:

```json
{
  "mcpServers": {
    "macpilot": {
      "type": "stdio",
      "command": "/absolute/path/to/macpilot/.build/release/macpilot"
    }
  }
}
```

Fully quit and relaunch Claude Code (not just a new session — MCP connections are established at app launch). In a new conversation, Claude will see 14 tools prefixed with `mcp__macpilot__`.

You can verify the server is online from a fresh conversation by asking Claude to call `display_list` — it should return all your connected monitors.

## How to use it

The normal loop is:

1. **`screen_context`** — returns a JPEG screenshot plus the frontmost app's interactive AX elements (buttons, text fields, menu items) with their frames in global Quartz coordinates (top-left origin).
2. **`pointer`** or **`keyboard_*`** / **`menu_invoke`** — act on a target, picking coordinates from the AX frames (not from visual guesswork on the screenshot).
3. **`wait_for_element`** — block until UI settles, instead of re-screenshotting in a loop.

The LLM shouldn't need to estimate pixels from the image — the AX element list already hands it `{role, label, frame}` for every clickable thing on screen.

## Tools

| Tool | What it does |
|------|---|
| `screen_context` | JPEG + interactive AX elements + cursor + active app. Takes optional `display_id`; defaults to the display containing the frontmost window. |
| `display_list` | Enumerate connected displays (ID, bounds, main/builtin flags, scale factor). |
| `pointer` | Execute a sequence of `{move, click, down, up, drag, scroll}` events. |
| `keyboard_type` | Unicode text input (batched; fast for long URLs). |
| `keyboard_press` | Key combo: `return`, `escape`, `cmd+n`, `cmd+shift+z`, arrows, f-keys… |
| `clipboard_get` / `clipboard_set` | Read or write the pasteboard. Combine with `cmd+v` for huge pastes. |
| `menu_invoke` | Walk the menu bar by path, e.g. `["File", "New from link"]`. AX press action — no coordinates. |
| `window_focus` | Activate an app and optionally raise a window by title substring. |
| `wait` | Sleep N milliseconds. |
| `wait_for_element` | Poll the AX tree until an element matching role/label/title appears. |
| `applications_list` | Running user-facing apps with pid/bundle/path. |
| `applications_open` | Open or focus an app by bundle id, name, or path. |
| `applications_terminate` | Terminate (or force-terminate) an app. |

## Coordinates

All coordinates are **Quartz global** — origin at the top-left of the primary display, Y increases downward, all displays live in one coordinate space. This is the native system for both the macOS Accessibility API and `CGEvent`, so AX frames from `screen_context` can be fed straight into `pointer` without conversion. Negative X or Y is valid (displays arranged to the left of or above the primary).

## Design notes

- **Display capture only, never per-window.** `SCContentFilter(desktopIndependentWindow:)` crashes (SkyLight assertion in `SLSGetDisplaysWithRect`) when the window's internal state is transient — sheets, modals, animations. Always filter by `display`.
- **Raw CF Accessibility API**, no `AXSwift` dependency. Keeps the binary small and surface area tight.
- **Filtered AX tree.** Structural wrappers (`AXRow`, `AXCell`) and decorative `AXImage` nodes are dropped. Elements without any labeling signal (`title`/`label`/`identifier`) are dropped. Capped at 100 elements, depth 12, clipped to the target display's bounds.
- **One JPEG pipeline.** Target 3 MB. Quality steps from 0.8 down to 0.3; only then does resolution scale down. Much cheaper on context than fixed-resolution PNG.
- **Coordinate-free AX actions only where they beat clicks.** `menu_invoke` and `window_focus` use `AXUIElementPerformAction(kAXPressAction / kAXRaiseAction)` because menu bars and window raising don't map cleanly to coordinates. Every other interaction is `CGEvent` at coordinates from the AX tree — same system, one source of truth.

## Version

Current: **0.3.0**. See `Sources/macpilot/Macpilot.swift`.

## License

MIT.
