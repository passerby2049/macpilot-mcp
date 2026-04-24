import AppKit
import Foundation

final class ClipboardService {
    func get() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    func set(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
