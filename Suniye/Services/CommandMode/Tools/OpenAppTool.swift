import AppKit

/// Launches or activates an app by name. Seam so the tool is unit-testable.
@MainActor
protocol AppLaunching {
    func launchOrActivate(_ name: String) -> Bool
}

struct SystemAppLauncher: AppLaunching {
    func launchOrActivate(_ name: String) -> Bool {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            return running.activate(options: [.activateAllWindows])
        }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
            ?? NSWorkspace.shared.fullPath(forApplication: name).map { URL(fileURLWithPath: $0) }
        guard let url else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

struct OpenAppTool: AgentTool {
    let name = "open_app"
    let risk: RiskTier = .benign
    let launcher: AppLaunching

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let app = arguments["name"], !app.isEmpty else {
            throw CommandModeError.malformedToolCall("open_app needs 'name'")
        }
        let ok = launcher.launchOrActivate(app)
        return ToolResult(output: ok ? "opened \(app)" : "could not open \(app)", isTerminal: false)
    }
}
