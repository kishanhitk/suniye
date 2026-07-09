import AppKit

/// Launches or activates an app by name. Seam so the tool is unit-testable.
/// `async` because launching settles the frontmost app before returning, so the
/// loop's next `read_screen` sees the app it just opened — not the previous one.
@MainActor
protocol AppLaunching {
    func launchOrActivate(_ name: String) async -> Bool
}

struct SystemAppLauncher: AppLaunching {
    /// How long to wait for the launched app to actually become frontmost. Cold
    /// launches settle in well under this; if it's exceeded we return anyway and
    /// the agent simply reads whatever is frontmost on the next turn.
    private let settleTimeout: TimeInterval

    init(settleTimeout: TimeInterval = 2.5) {
        self.settleTimeout = settleTimeout
    }

    func launchOrActivate(_ name: String) async -> Bool {
        guard launch(name) else { return false }
        // The launch/activate above is asynchronous at the OS level — `open -a`
        // and `activate()` return before the app is frontmost. Without this wait
        // the very next `read_screen` races the switch and shows the OLD app, so
        // the model re-issues open_app (repeat-guard → stall) instead of acting on
        // what it just opened. Settling here fixes multi-step "open X then …".
        await waitUntilFrontmost(name)
        return true
    }

    private func launch(_ name: String) -> Bool {
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

    /// Polls (yielding the main actor via sleep) until the frontmost app's name
    /// loosely matches `name` — a loose match so fuzzy launches settle too
    /// ("chrome" → "Google Chrome"). Bounded by `settleTimeout`.
    private func waitUntilFrontmost(_ name: String) async {
        let deadline = Date().addingTimeInterval(settleTimeout)
        while Date() < deadline {
            if let front = NSWorkspace.shared.frontmostApplication?.localizedName,
               front.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(front) {
                AppLogger.shared.log(.info, "open_app: \(name) is frontmost")
                return
            }
            try? await Task.sleep(nanoseconds: 80_000_000) // 80 ms
        }
        AppLogger.shared.log(.info, "open_app: \(name) did not become frontmost within \(settleTimeout)s")
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
        let ok = await launcher.launchOrActivate(app)
        return ToolResult(output: ok ? "opened \(app)" : "could not open \(app)", isTerminal: false)
    }
}
