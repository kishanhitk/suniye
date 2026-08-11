import CoreGraphics
import Foundation

enum ComputerUseRuntimeError: LocalizedError, Equatable, Sendable {
    case screenLocked

    var errorDescription: String? {
        switch self {
        case .screenLocked:
            "The Mac is locked. Unlock it before continuing Computer Use."
        }
    }
}

struct ComputerUseRuntimeAuthorization: Equatable, Sendable {}

protocol ComputerUseRuntimeGuarding: Sendable {
    func prepareForObservation() async throws -> ComputerUseRuntimeAuthorization
    func validateAction(_ authorization: ComputerUseRuntimeAuthorization) async throws
}

protocol ComputerUseScreenLockChecking: Sendable {
    func isScreenLocked() async -> Bool
}

struct ComputerUseRuntimeGuard: ComputerUseRuntimeGuarding {
    private let screenLock: ComputerUseScreenLockChecking

    init(
        screenLock: ComputerUseScreenLockChecking = SystemComputerUseScreenLockChecker()
    ) {
        self.screenLock = screenLock
    }

    func prepareForObservation() async throws -> ComputerUseRuntimeAuthorization {
        try await requireUnlockedScreen()
        return ComputerUseRuntimeAuthorization()
    }

    func validateAction(_ authorization: ComputerUseRuntimeAuthorization) async throws {
        try await requireUnlockedScreen()
    }

    private func requireUnlockedScreen() async throws {
        guard !(await screenLock.isScreenLocked()) else {
            throw ComputerUseRuntimeError.screenLocked
        }
    }
}

struct SystemComputerUseScreenLockChecker: ComputerUseScreenLockChecking {
    typealias SessionDictionary = @Sendable () -> [String: Any]?

    private let sessionDictionary: SessionDictionary

    init(sessionDictionary: @escaping SessionDictionary = {
        CGSessionCopyCurrentDictionary() as? [String: Any]
    }) {
        self.sessionDictionary = sessionDictionary
    }

    func isScreenLocked() -> Bool {
        sessionDictionary()?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
