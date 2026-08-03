import Foundation
@testable import Suniye

final class Phase3StubApplicationCatalog: ComputerUseApplicationCatalog {
    func listApplications() -> [ComputerUseApplication] {
        []
    }

    func application(withID identifier: String) -> ComputerUseApplication? {
        nil
    }
}

final class Phase3ScriptedModelClient: ComputerUseModelClient {
    private var decisions: [ComputerUseModelDecision]
    private var errors: [Error]
    private(set) var requests: [ComputerUseModelRequest] = []
    var onDecide: ((ComputerUseModelRequest) throws -> Void)?

    init(
        decisions: [ComputerUseModelDecision] = [],
        errors: [Error] = []
    ) {
        self.decisions = decisions
        self.errors = errors
    }

    func decide(
        request: ComputerUseModelRequest,
        cancellation: ComputerUseCancellationToken
    ) async throws -> ComputerUseModelDecision {
        requests.append(request)
        try onDecide?(request)
        if !errors.isEmpty {
            throw errors.removeFirst()
        }
        guard !decisions.isEmpty else {
            throw ComputerUseModelError.requestFailed("no scripted decision")
        }
        return decisions.removeFirst()
    }
}

final class Phase3StubApprovalService: ComputerUseApprovalRequesting {
    private var decisions: [ComputerUseApprovalDecision]
    private(set) var requests: [ComputerUseApprovalRequest] = []
    var onRequest: ((ComputerUseApprovalRequest) -> Void)?

    init(decisions: [ComputerUseApprovalDecision]) {
        self.decisions = decisions
    }

    func requestApproval(
        _ request: ComputerUseApprovalRequest,
        cancellation: ComputerUseCancellationToken
    ) async -> ComputerUseApprovalDecision {
        requests.append(request)
        onRequest?(request)
        return decisions.isEmpty ? .deny : decisions.removeFirst()
    }
}

final class Phase3StubObservationService: ComputerUseObservationServicing {
    private var results: [ComputerUseObservation]
    let error: Error?
    private(set) var observeCount = 0
    private(set) var applicationIDs: [String] = []

    init(result: ComputerUseObservation, error: Error? = nil) {
        results = [result]
        self.error = error
    }

    init(results: [ComputerUseObservation], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func observe(
        applicationID: String,
        includeScreenshot: Bool,
        configuration: ComputerUseObservationConfiguration,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        observeCount += 1
        applicationIDs.append(applicationID)
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseObservationError.cancelled
        }
        guard !results.isEmpty else {
            throw ComputerUseObservationError.noWindow(applicationID)
        }
        return results.count == 1 ? results[0] : results.removeFirst()
    }
}

final class Phase3StubActionService: ComputerUseActionServicing {
    private var errors: [Error]
    private(set) var actions: [ComputerUseAction] = []
    private(set) var requestIDs: [UUID] = []
    var onExecute: ((ComputerUseAction) throws -> Void)?

    init(errors: [Error] = []) {
        self.errors = errors
    }

    func execute(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approval: ComputerUseApprovalGrant,
        requestID: UUID,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseActionResult {
        if let onExecute {
            try onExecute(action)
        }
        if !errors.isEmpty {
            throw errors.removeFirst()
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        actions.append(action)
        requestIDs.append(requestID)
        return ComputerUseActionResult(
            action: action,
            target: observation.target,
            completedAt: Date(timeIntervalSince1970: 20_000)
        )
    }
}

final class Phase3StubWindowDiscovery: ComputerUseWindowDiscovering {
    var windows: [ComputerUseWindow]

    init(windows: [ComputerUseWindow]) {
        self.windows = windows
    }

    func listWindows(for application: ComputerUseApplication) -> [ComputerUseWindow] {
        windows
    }
}

final class Phase3Clock {
    private var values: [Date]
    private var last: Date

    init(values: [Date]) {
        self.values = values
        last = values.last ?? Date(timeIntervalSince1970: 0)
    }

    func next() -> Date {
        if values.isEmpty {
            return last
        }
        last = values.removeFirst()
        return last
    }
}

enum Phase3TestError: Error {
    case sleepFailed
}

func makePhase3Observation(generation: UInt64) -> ComputerUseObservation {
    let application = ComputerUseApplication(
        id: "com.example.target#42",
        bundleIdentifier: "com.example.target",
        displayName: "Target App",
        processIdentifier: 42,
        isRunning: true,
        isActive: true,
        launchDate: nil
    )
    let window = ComputerUseWindow(
        id: 7,
        title: "Target Window",
        ownerProcessIdentifier: application.processIdentifier,
        bounds: ComputerUseRect(x: 0, y: 0, width: 640, height: 480),
        layer: 0,
        isOnScreen: true,
        isKeyWindow: true
    )
    return ComputerUseObservation(
        generation: generation,
        capturedAt: Date(timeIntervalSince1970: 1_000 + Double(generation)),
        target: ComputerUseTarget(application: application, window: window),
        accessibility: ComputerUseAXSnapshot(
            text: "[0] role=AXButton title=OK",
            elements: [ComputerUseAXElement(
                index: 0,
                role: "AXButton",
                subrole: nil,
                title: "OK",
                description: nil,
                value: nil,
                isEnabled: true,
                isFocused: false,
                isSelected: false,
                bounds: ComputerUseRect(x: 40, y: 40, width: 100, height: 40),
                actions: ["AXPress"],
                childIndexes: []
            )],
            wasTruncated: false
        ),
        screenshot: nil
    )
}
