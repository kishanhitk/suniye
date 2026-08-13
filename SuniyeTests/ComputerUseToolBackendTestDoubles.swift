import Foundation
@testable import Suniye

struct BackendFixture {
    let applications: StubActionApplicationCatalog
    let windows: MutableActionWindowDiscovery
    let observations: StubComputerUseObserving
    let actions: RecordingComputerUseActions
    let settler: RecordingComputerUseSettler
    let runtimeGuard: ControllableComputerUseRuntimeGuard
}

func backendFixture(actionError: Error? = nil) -> BackendFixture {
    let context = computerUseTestActionContext()
    let observation = ComputerUseObservation(
        target: context.target,
        state: ComputerUseAppState(
            app: "Calculator",
            screenshot: context.screenshot?.url,
            text: "0: AXWindow"
        ),
        revision: context.revision,
        screenshot: context.screenshot
    )
    return BackendFixture(
        applications: StubActionApplicationCatalog(application: context.target.application),
        windows: MutableActionWindowDiscovery(window: context.target.window),
        observations: StubComputerUseObserving(observation: observation),
        actions: RecordingComputerUseActions(error: actionError),
        settler: RecordingComputerUseSettler(),
        runtimeGuard: ControllableComputerUseRuntimeGuard()
    )
}

actor StubActionApplicationCatalog: ComputerUseApplicationCatalogProviding {
    let application: ComputerUseApplicationRecord
    private var reopenError: Error?
    private(set) var reopenCount = 0

    init(application: ComputerUseApplicationRecord) {
        self.application = application
    }

    func listApps() -> [ComputerUseApplication] {
        [application.publicApplication]
    }

    func resolveOrLaunch(_ identifier: String) -> ComputerUseApplicationRecord {
        application
    }

    func reopen(_ application: ComputerUseApplicationRecord) throws -> ComputerUseApplicationRecord {
        reopenCount += 1
        if let reopenError {
            throw reopenError
        }
        return self.application
    }

    func failReopen(with error: Error) {
        reopenError = error
    }
}

actor MutableActionWindowDiscovery: ComputerUseWindowDiscovering {
    private var window: ComputerUseWindow
    private var unavailableResponsesRemaining = 0
    private(set) var callCount = 0

    init(window: ComputerUseWindow) {
        self.window = window
    }

    func orderedWindows(processIdentifier: Int32) -> [ComputerUseWindow] {
        callCount += 1
        if unavailableResponsesRemaining > 0 {
            unavailableResponsesRemaining -= 1
            return []
        }
        return [window]
    }

    func hideForNextCalls(_ count: Int) {
        unavailableResponsesRemaining = count
    }

    func replaceWindowID(with id: UInt32) {
        window = ComputerUseWindow(
            id: id,
            ownerProcessIdentifier: window.ownerProcessIdentifier,
            title: window.title,
            bounds: window.bounds,
            layer: window.layer,
            isOnScreen: window.isOnScreen,
            accessibilityOrdinal: window.accessibilityOrdinal,
            isFocused: window.isFocused,
            isMain: window.isMain
        )
    }
}

actor StubComputerUseObserving: ComputerUseObserving {
    nonisolated let observation: ComputerUseObservation

    init(observation: ComputerUseObservation) {
        self.observation = observation
    }

    func observe(
        application: ComputerUseApplicationRecord,
        requestedIdentifier: String,
        disableDiff: Bool
    ) -> ComputerUseObservation {
        observation
    }
}

actor ControllableComputerUseObserving: ComputerUseObserving {
    let observation: ComputerUseObservation
    private var shouldFail = false
    private var failuresRemaining = 0

    init(observation: ComputerUseObservation) {
        self.observation = observation
    }

    func failSubsequentObservations() {
        shouldFail = true
    }

    func failNextObservation() {
        failuresRemaining = 1
    }

    func observe(
        application: ComputerUseApplicationRecord,
        requestedIdentifier: String,
        disableDiff: Bool
    ) throws -> ComputerUseObservation {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw ComputerUseObservationError.noWindow(requestedIdentifier)
        }
        if shouldFail {
            throw ComputerUseObservationError.noWindow(requestedIdentifier)
        }
        return observation
    }
}

actor RecordingComputerUseActions: ComputerUseActionServing {
    enum Call: Equatable {
        case click(ComputerUseClickRequest)
        case secondaryAction(index: Int, action: String)
        case setValue(index: Int, value: String)
        case selectText(
            index: Int,
            text: String,
            prefix: String?,
            suffix: String?,
            selectionType: ComputerUseTextSelectionType
        )
        case scroll(index: Int, direction: ComputerUseScrollDirection, pages: Double)
        case drag(fromX: Double, fromY: Double, toX: Double, toY: Double)
        case pressKey(String)
        case typeText(String)
    }

    private let error: Error?
    private(set) var calls: [Call] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func click(_ request: ComputerUseClickRequest, context: ComputerUseActionContext) throws {
        try throwIfNeeded()
        calls.append(.click(request))
    }

    func performSecondaryAction(
        _ action: String,
        elementIndex: Int,
        context: ComputerUseActionContext
    ) throws {
        try throwIfNeeded()
        calls.append(.secondaryAction(index: elementIndex, action: action))
    }

    func setValue(_ value: String, elementIndex: Int, context: ComputerUseActionContext) throws {
        try throwIfNeeded()
        calls.append(.setValue(index: elementIndex, value: value))
    }

    func selectText(
        _ text: String,
        elementIndex: Int,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        context: ComputerUseActionContext
    ) throws {
        try throwIfNeeded()
        calls.append(
            .selectText(
                index: elementIndex,
                text: text,
                prefix: prefix,
                suffix: suffix,
                selectionType: selectionType
            )
        )
    }

    func scroll(
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double,
        context: ComputerUseActionContext
    ) throws {
        try throwIfNeeded()
        calls.append(.scroll(index: elementIndex, direction: direction, pages: pages))
    }

    func drag(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        context: ComputerUseActionContext
    ) throws {
        try throwIfNeeded()
        calls.append(.drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY))
    }

    func pressKey(_ key: String, context: ComputerUseActionContext) throws {
        try throwIfNeeded()
        calls.append(.pressKey(key))
    }

    func typeText(_ text: String, context: ComputerUseActionContext) throws {
        try throwIfNeeded()
        calls.append(.typeText(text))
    }

    private func throwIfNeeded() throws {
        if let error {
            throw error
        }
    }
}

actor RecordingComputerUseSettler: ComputerUseActionSettling {
    private(set) var waitCount = 0

    func waitForUIToSettle(target: ComputerUseObservedTarget) {
        waitCount += 1
    }
}

actor ControllableComputerUseRuntimeGuard: ComputerUseRuntimeGuarding {
    private var isScreenLocked: Bool
    private(set) var checkCount = 0

    init(isScreenLocked: Bool = false) {
        self.isScreenLocked = isScreenLocked
    }

    func ensureScreenUnlocked() throws {
        guard !isScreenLocked else {
            throw ComputerUseRuntimeError.screenLocked
        }
        checkCount += 1
    }

    func recordPhysicalInput() {}
}

actor ScriptedComputerUseLoadingState: ComputerUseLoadingStateChecking {
    private var states: [Bool]
    private(set) var checkCount = 0

    init(states: [Bool]) {
        self.states = states
    }

    func isLoading(_ target: ComputerUseObservedTarget) -> Bool {
        checkCount += 1
        return states.isEmpty ? false : states.removeFirst()
    }
}

actor RecordingComputerUseSleeper: ComputerUseSleeping {
    private(set) var delays: [Duration] = []

    func sleep(for duration: Duration) {
        delays.append(duration)
    }
}
