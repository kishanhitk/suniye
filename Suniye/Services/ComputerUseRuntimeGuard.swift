import CoreGraphics
import Foundation

enum ComputerUseRuntimeError: LocalizedError, Equatable, Sendable {
    case screenLocked
    case userIntervened

    var errorDescription: String? {
        switch self {
        case .screenLocked:
            "The Mac is locked. Unlock it before continuing Computer Use."
        case .userIntervened:
            "Computer Use stopped because you used your Mac."
        }
    }
}

struct ComputerUseRuntimeAuthorization: Equatable, Sendable {
    let physicalInputSnapshot: ComputerUsePhysicalInputSnapshot
}

struct ComputerUsePhysicalInputSnapshot: Equatable, Sendable {
    let eventCounts: [UInt32]
}

protocol ComputerUseRuntimeGuarding: Sendable {
    func prepareForObservation() async throws -> ComputerUseRuntimeAuthorization
    func validateAction(_ authorization: ComputerUseRuntimeAuthorization) async throws
}

protocol ComputerUseScreenLockChecking: Sendable {
    func isScreenLocked() async -> Bool
}

protocol ComputerUsePhysicalInputSampling: Sendable {
    func snapshot() async -> ComputerUsePhysicalInputSnapshot
}

struct ComputerUseRuntimeGuard: ComputerUseRuntimeGuarding {
    private let screenLock: ComputerUseScreenLockChecking
    private let physicalInput: ComputerUsePhysicalInputSampling

    init(
        screenLock: ComputerUseScreenLockChecking = SystemComputerUseScreenLockChecker(),
        physicalInput: ComputerUsePhysicalInputSampling =
            SystemComputerUsePhysicalInputSampler()
    ) {
        self.screenLock = screenLock
        self.physicalInput = physicalInput
    }

    func prepareForObservation() async throws -> ComputerUseRuntimeAuthorization {
        try await requireUnlockedScreen()
        return ComputerUseRuntimeAuthorization(
            physicalInputSnapshot: await physicalInput.snapshot()
        )
    }

    func validateAction(_ authorization: ComputerUseRuntimeAuthorization) async throws {
        try await requireUnlockedScreen()
        guard await physicalInput.snapshot() == authorization.physicalInputSnapshot else {
            throw ComputerUseRuntimeError.userIntervened
        }
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

struct SystemComputerUsePhysicalInputSampler: ComputerUsePhysicalInputSampling {
    typealias Counter = @Sendable (CGEventType) -> UInt32

    private static let monitoredEvents: [CGEventType] = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
        .keyDown,
        .flagsChanged,
    ]

    private let counter: Counter

    init(counter: @escaping Counter = { eventType in
        CGEventSource.counterForEventType(.hidSystemState, eventType: eventType)
    }) {
        self.counter = counter
    }

    func snapshot() -> ComputerUsePhysicalInputSnapshot {
        ComputerUsePhysicalInputSnapshot(
            eventCounts: Self.monitoredEvents.map(counter)
        )
    }
}
