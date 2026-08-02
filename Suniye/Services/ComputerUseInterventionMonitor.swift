import AppKit

struct SystemComputerUseInterventionMonitor: ComputerUseInterventionMonitoring {
    private let windowDiscovery: ComputerUseWindowDiscovering
    private let frontmostProcessIdentifierProvider: () -> Int32?

    init(
        windowDiscovery: ComputerUseWindowDiscovering = SystemComputerUseWindowDiscovery(),
        frontmostProcessIdentifierProvider: @escaping () -> Int32? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.windowDiscovery = windowDiscovery
        self.frontmostProcessIdentifierProvider = frontmostProcessIdentifierProvider
    }

    func check(target: ComputerUseTarget) -> ComputerUseIntervention? {
        guard frontmostProcessIdentifierProvider() == target.application.processIdentifier else {
            return .frontmostApplicationChanged
        }

        guard let currentWindow = windowDiscovery
            .listWindows(for: target.application)
            .first(where: { $0.id == target.window.id }) else {
            return .targetWindowChanged
        }

        guard currentWindow.isKeyWindow else {
            return .targetWindowChanged
        }

        return nil
    }
}
