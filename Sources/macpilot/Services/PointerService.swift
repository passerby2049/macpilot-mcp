import AppKit
import CoreGraphics
import Foundation

/// CGEvent-based pointer control. All input coordinates are Quartz (top-left origin),
/// matching what CGEvent expects natively and what AX API returns.
final class PointerService {

    enum Button: String, Codable {
        case left, right, middle
        var cgButton: CGMouseButton {
            switch self {
            case .left: return .left
            case .right: return .right
            case .middle: return .center
            }
        }
        var down: CGEventType {
            switch self {
            case .left: return .leftMouseDown
            case .right: return .rightMouseDown
            case .middle: return .otherMouseDown
            }
        }
        var up: CGEventType {
            switch self {
            case .left: return .leftMouseUp
            case .right: return .rightMouseUp
            case .middle: return .otherMouseUp
            }
        }
    }

    // MARK: - Move

    func move(to p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Click

    /// Click at `p`. If `count` > 1, posts a proper multi-click sequence.
    func click(at p: CGPoint, button: Button = .left, count: Int = 1) throws {
        guard count >= 1 else { throw AutomationError.invalidInput("count must be >= 1") }
        CGWarpMouseCursorPosition(p)
        for i in 1...count {
            try postMouse(button.down, at: p, button: button, clickState: i)
            try postMouse(button.up,   at: p, button: button, clickState: i)
        }
    }

    func down(at p: CGPoint, button: Button = .left) throws {
        CGWarpMouseCursorPosition(p)
        try postMouse(button.down, at: p, button: button, clickState: 1)
    }

    func up(at p: CGPoint, button: Button = .left) throws {
        CGWarpMouseCursorPosition(p)
        try postMouse(button.up, at: p, button: button, clickState: 1)
    }

    // MARK: - Drag

    func drag(from: CGPoint, to: CGPoint, button: Button = .left) throws {
        try down(at: from, button: button)
        // Post a dragged event so apps see it as a drag, not teleport.
        let dragged: CGEventType = (button == .left) ? .leftMouseDragged
            : (button == .right ? .rightMouseDragged : .otherMouseDragged)
        try postMouse(dragged, at: to, button: button, clickState: 1)
        try up(at: to, button: button)
    }

    // MARK: - Scroll

    /// Scroll at `p` by pixel deltas (positive dx = right, positive dy = up).
    func scroll(at p: CGPoint, dx: Int, dy: Int) throws {
        CGWarpMouseCursorPosition(p)
        guard let ev = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel, wheelCount: 2,
            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0
        ) else { throw AutomationError.eventCreationFailed }
        ev.post(tap: .cghidEventTap)
    }

    // MARK: - Internal

    private func postMouse(_ type: CGEventType, at p: CGPoint, button: Button, clickState: Int) throws {
        guard let ev = CGEvent(
            mouseEventSource: nil, mouseType: type,
            mouseCursorPosition: p, mouseButton: button.cgButton
        ) else { throw AutomationError.eventCreationFailed }
        ev.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        ev.post(tap: .cghidEventTap)
    }
}
