import Foundation

/// Maps Computer Use phases to floating-indicator states and owns the
/// completed-flash reset timer. The caller decides whether the shared
/// indicator is available (an active dictation session takes priority);
/// this type decides what to show.
@MainActor
final class ComputerUseIndicatorPresenter {
    private let completedFlashDuration: Duration
    private let currentState: () -> FloatingIndicatorState
    private let setState: (FloatingIndicatorState) -> Void
    private let showError: (String) -> Void
    private var resetTask: Task<Void, Never>?

    init(
        completedFlashDuration: Duration = .milliseconds(1_400),
        currentState: @escaping () -> FloatingIndicatorState,
        setState: @escaping (FloatingIndicatorState) -> Void,
        showError: @escaping (String) -> Void
    ) {
        self.completedFlashDuration = completedFlashDuration
        self.currentState = currentState
        self.setState = setState
        self.showError = showError
    }

    func handlePhase(
        _ phase: ComputerUseCoordinatorPhase,
        errorMessage: String?,
        indicatorAvailable: Bool
    ) {
        switch phase {
        case .running:
            cancelReset()
            guard indicatorAvailable else { return }
            setState(.computerUseWorking)
        case .completed:
            guard indicatorAvailable else { return }
            showCompletedFlash()
        case .cancelled:
            cancelReset()
            guard indicatorAvailable else { return }
            setState(.idle)
        case .failed:
            cancelReset()
            guard indicatorAvailable else { return }
            showError(errorMessage ?? "Computer Use failed")
        case .idle, .checkingPermissions, .requestingPermission, .ready:
            break
        }
    }

    func cancelReset() {
        resetTask?.cancel()
        resetTask = nil
    }

    private func showCompletedFlash() {
        cancelReset()
        setState(.computerUseCompleted)
        resetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: completedFlashDuration)
            guard !Task.isCancelled else { return }
            defer { resetTask = nil }
            guard currentState() == .computerUseCompleted else { return }
            setState(.idle)
        }
    }
}
