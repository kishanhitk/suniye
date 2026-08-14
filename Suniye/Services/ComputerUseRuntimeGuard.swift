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

protocol ComputerUseRuntimeGuarding: Sendable {
    func ensureScreenUnlocked() async throws
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

    func ensureScreenUnlocked() async throws {
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
