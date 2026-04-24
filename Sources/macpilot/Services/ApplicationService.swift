import AppKit
import Foundation

final class ApplicationService {

    struct AppInfo: Codable {
        let name: String?
        let bundleIdentifier: String?
        let path: String?
        let processId: pid_t
    }

    func list() -> [AppInfo] {
        let privatePrefix = "/System/Library/PrivateFrameworks/"
        return NSWorkspace.shared.runningApplications.compactMap { app in
            let path = app.bundleURL?.path
            if let path, path.hasPrefix(privatePrefix) { return nil }
            return AppInfo(
                name: app.localizedName,
                bundleIdentifier: app.bundleIdentifier,
                path: path,
                processId: app.processIdentifier
            )
        }
    }

    /// Open or focus an app. Provide one of: bundleIdentifier, name, path.
    func open(bundleIdentifier: String?, name: String?, path: String?) async throws {
        let ws = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        if let bundleIdentifier {
            if let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first {
                running.activate(options: [.activateAllWindows])
                return
            }
            guard let url = ws.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw AutomationError.appNotFound(bundleIdentifier)
            }
            _ = try await ws.openApplication(at: url, configuration: config)
            return
        }

        if let name {
            if let running = ws.runningApplications.first(where: {
                ($0.localizedName ?? "").localizedCaseInsensitiveContains(name)
            }) {
                running.activate(options: [.activateAllWindows])
                return
            }
            // Fall back to /Applications lookup.
            let candidate = "/Applications/\(name).app"
            if FileManager.default.fileExists(atPath: candidate) {
                _ = try await ws.openApplication(at: URL(fileURLWithPath: candidate), configuration: config)
                return
            }
            throw AutomationError.appNotFound(name)
        }

        if let path {
            _ = try await ws.openApplication(at: URL(fileURLWithPath: path), configuration: config)
            return
        }

        throw AutomationError.invalidInput("Provide bundle_identifier, name, or path.")
    }

    func terminate(bundleIdentifier: String?, name: String?, path: String?, force: Bool) throws {
        let ws = NSWorkspace.shared
        let target: NSRunningApplication?
        if let bundleIdentifier {
            target = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier).first
        } else if let name {
            target = ws.runningApplications.first {
                ($0.localizedName ?? "").localizedCaseInsensitiveContains(name)
            }
        } else if let path {
            target = ws.runningApplications.first { $0.bundleURL?.path == path }
        } else {
            throw AutomationError.invalidInput("Provide bundle_identifier, name, or path.")
        }
        guard let app = target else {
            throw AutomationError.appNotFound(bundleIdentifier ?? name ?? path ?? "?")
        }
        if force { app.forceTerminate() } else { app.terminate() }
    }
}
