import Foundation

protocol ComputerUseActionSettling: Sendable {
    func waitForUIToSettle(target: ComputerUseObservedTarget) async throws
}

protocol ComputerUseLoadingStateChecking: Sendable {
    func isLoading(_ target: ComputerUseObservedTarget) async -> Bool
}

protocol ComputerUseSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemComputerUseActionSettler: ComputerUseActionSettling {
    private let loadingState: ComputerUseLoadingStateChecking
    private let sleeper: ComputerUseSleeping
    private let initialDelay: Duration
    private let loadingPollDelay: Duration
    private let maximumLoadingChecks: Int

    init(
        loadingState: ComputerUseLoadingStateChecking =
            SystemComputerUseLoadingStateChecker(),
        sleeper: ComputerUseSleeping = SystemComputerUseSleeper(),
        initialDelay: Duration = .seconds(1),
        loadingPollDelay: Duration = .milliseconds(500),
        maximumLoadingChecks: Int = 10
    ) {
        self.loadingState = loadingState
        self.sleeper = sleeper
        self.initialDelay = initialDelay
        self.loadingPollDelay = loadingPollDelay
        self.maximumLoadingChecks = max(0, maximumLoadingChecks)
    }

    func waitForUIToSettle(target: ComputerUseObservedTarget) async throws {
        try await sleeper.sleep(for: initialDelay)
        for _ in 0 ..< maximumLoadingChecks {
            guard await loadingState.isLoading(target) else {
                return
            }
            try await sleeper.sleep(for: loadingPollDelay)
        }
    }
}

struct SystemComputerUseLoadingStateChecker: ComputerUseLoadingStateChecking {
    private let accessibility: ComputerUseAccessibilitySnapshotProviding

    init(
        accessibility: ComputerUseAccessibilitySnapshotProviding =
            SystemComputerUseAccessibilitySnapshotProvider()
    ) {
        self.accessibility = accessibility
    }

    func isLoading(_ target: ComputerUseObservedTarget) async -> Bool {
        guard let processIdentifier = target.application.processIdentifier,
              let snapshot = try? await accessibility.snapshot(
                  processIdentifier: processIdentifier,
                  windowOrdinal: target.window.accessibilityOrdinal
              ) else {
            return false
        }
        return snapshot.roots.contains(where: containsLoadingIndicator)
    }

    private func containsLoadingIndicator(_ node: ComputerUseAXNode) -> Bool {
        if node.role == "AXProgressIndicator" || node.role == "AXBusyIndicator" {
            return true
        }
        return node.children.contains(where: containsLoadingIndicator)
    }
}

struct SystemComputerUseSleeper: ComputerUseSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
