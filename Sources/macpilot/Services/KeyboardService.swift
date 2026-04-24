import CoreGraphics
import Foundation

/// CGEvent keyboard input — both Unicode text insertion and virtual-key combos.
final class KeyboardService {

    /// Type text as Unicode. Batches up to 20 UTF-16 code units per event (CGEvent limit),
    /// so long URLs / sentences don't stall one char at a time.
    func type(_ text: String) throws {
        let utf16 = Array(text.utf16)
        var index = 0
        while index < utf16.count {
            let end = min(index + 20, utf16.count)
            let slice = Array(utf16[index..<end])
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else { throw AutomationError.eventCreationFailed }
            down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: slice)
            up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: slice)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            index = end
        }
    }

    /// Press a key or combo: "return", "escape", "cmd+n", "cmd+shift+z", etc.
    func press(_ combo: String) throws {
        guard let (flags, key) = CarbonKeys.parseCombo(combo) else {
            throw AutomationError.unknownKey(combo)
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up   = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        else { throw AutomationError.eventCreationFailed }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
