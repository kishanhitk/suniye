import AppKit

/// Launches or activates an app by name. Seam so the tool is unit-testable.
@MainActor
protocol AppLaunching {
    func launchOrActivate(_ name: String) -> Bool
}

struct SystemAppLauncher: AppLaunching {
    func launchOrActivate(_ name: String) -> Bool {
        // Already running → activate best-effort and report success. Do NOT gate on
        // activate()'s return value: on recent macOS it returns false even when the
        // app IS activated, which wrongly read as "could not open".
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            running.activate()
            AppLogger.shared.log(.info, "open_app: activated already-running \(name)")
            return true
        }
        // Primary: `open -a <name>` — LaunchServices' fuzzy name resolution launches
        // or activates stock apps ("System Settings") and most installs by name.
        if runOpen(["-a", name]) {
            AppLogger.shared.log(.info, "open_app: launched \(name) via open -a")
            return true
        }
        // Fallback: resolve a .app URL and open it in-process (open(_:) is synchronous
        // and returns a real success Bool, unlike openApplication(at:)).
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) ?? Self.appURL(named: name) {
            let ok = NSWorkspace.shared.open(url)
            AppLogger.shared.log(.info, "open_app: NSWorkspace.open(\(url.lastPathComponent)) = \(ok)")
            return ok
        }
        AppLogger.shared.log(.warning, "open_app: could not resolve app named \(name)")
        return false
    }

    private func runOpen(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            AppLogger.shared.log(.warning, "open_app: /usr/bin/open failed: \(error)")
            return false
        }
    }

    private static func appURL(named name: String) -> URL? {
        for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       "\(NSHomeDirectory())/Applications"] {
            let candidate = URL(fileURLWithPath: folder).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

struct OpenAppTool: AgentTool {
    let name = "open_app"
    let risk: RiskTier = .benign
    let launcher: AppLaunching

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        // Accept the correct key ("name") and the common wrong one ("app").
        let raw = (arguments["name"] ?? arguments["app"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let app = raw, !app.isEmpty else {
            throw CommandModeError.malformedToolCall("open_app needs 'name'")
        }
        let ok = launcher.launchOrActivate(app)
        return ToolResult(output: ok ? "opened \(app)" : "could not open \(app)", isTerminal: false)
    }
}
