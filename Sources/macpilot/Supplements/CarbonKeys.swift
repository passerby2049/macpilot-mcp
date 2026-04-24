import Carbon.HIToolbox
import CoreGraphics

enum CarbonKeys {
    /// Maps a user-friendly key name to a virtual key code. Case-insensitive.
    static func keyCode(for name: String) -> CGKeyCode? {
        let lower = name.lowercased()
        return table[lower]
    }

    /// Returns (modifier flags, base key). Parses `cmd+shift+k`, `control+return`, etc.
    static func parseCombo(_ combo: String) -> (CGEventFlags, CGKeyCode)? {
        let parts = combo.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let last = parts.last, let key = keyCode(for: last) else { return nil }

        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "meta":      flags.insert(.maskCommand)
            case "shift":                        flags.insert(.maskShift)
            case "opt", "option", "alt":        flags.insert(.maskAlternate)
            case "ctrl", "control":              flags.insert(.maskControl)
            case "fn":                           flags.insert(.maskSecondaryFn)
            default: return nil
            }
        }
        return (flags, key)
    }

    private static let table: [String: CGKeyCode] = [
        // Letters
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
        "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6,
        // Digits
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
        "8": 28, "9": 25,
        // Named
        "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51,
        "backspace": 51, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "forwarddelete": 117,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        // Punctuation
        "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39,
        ",": 43, ".": 47, "/": 44, "`": 50,
    ]
}
