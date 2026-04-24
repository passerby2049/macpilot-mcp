import Foundation

enum AutomationError: LocalizedError {
    case noScreenCapturePermission
    case noAccessibilityPermission
    case noDisplayFound
    case appNotFound(String)
    case noFrontmostApp
    case eventCreationFailed
    case unknownKey(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .noScreenCapturePermission:  return "No screen recording permission. Grant in System Settings → Privacy & Security → Screen Recording."
        case .noAccessibilityPermission:  return "No accessibility permission. Grant in System Settings → Privacy & Security → Accessibility."
        case .noDisplayFound:             return "No display found."
        case .appNotFound(let s):         return "App not found: \(s)"
        case .noFrontmostApp:             return "No frontmost application."
        case .eventCreationFailed:        return "Failed to create CGEvent."
        case .unknownKey(let k):          return "Unknown key: \(k)"
        case .invalidInput(let s):        return "Invalid input: \(s)"
        }
    }
}
