import XCTest
@testable import Suniye

final class ComputerUseToolBackendTests: XCTestCase {
    func testDefaultBackendCanBeConstructedWithoutStartingSystemWork() {
        _ = ComputerUseToolBackend()
    }

    func testSystemSettlerIsCancellationAware() async {
        let task = Task {
            try await SystemComputerUseActionSettler().waitForUIToSettle()
        }
        task.cancel()

        await XCTAssertThrowsErrorAsync(try await task.value)
    }

    func testListsApplicationsThroughCatalog() async throws {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler
        )

        let applications = try await backend.listApps()

        XCTAssertEqual(applications, [computerUseTestActionContext().target.application.publicApplication])
    }

    func testObservationFeedsStateAndEnablesAnActionForTheSameWindow() async throws {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler
        )

        let state = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.typeText(app: "Calculator", text: "42")

        let actionCalls = await fixture.actions.calls
        let waitCount = await fixture.settler.waitCount
        XCTAssertEqual(state.text, "0: AXWindow")
        XCTAssertEqual(actionCalls, [.typeText("42")])
        XCTAssertEqual(waitCount, 1)
    }

    func testActionRequiresAReferenceObservation() async {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler
        )

        do {
            try await backend.pressKey(app: "Calculator", key: "Return")
            XCTFail("Expected an observation-required error")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .observationRequired("Calculator"))
        }
    }

    func testSuccessfulActionConsumesObservation() async throws {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.typeText(app: "Calculator", text: "42")

        do {
            try await backend.pressKey(app: "Calculator", key: "Return")
            XCTFail("Expected a fresh observation requirement")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .observationRequired("Calculator"))
        }
    }

    func testFailedRefreshInvalidatesThePreviousObservation() async throws {
        let fixture = backendFixture()
        let observations = ControllableComputerUseObserving(observation: fixture.observations.observation)
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: observations,
            actions: fixture.actions,
            settler: fixture.settler
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        await observations.failSubsequentObservations()

        await XCTAssertThrowsErrorAsync(
            _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        )

        do {
            try await backend.typeText(app: "Calculator", text: "42")
            XCTFail("Expected the failed refresh to invalidate the previous observation")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .observationRequired("Calculator"))
        }
    }

    func testForwardsEveryActionAfterFreshObservation() async throws {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler
        )
        let click = ComputerUseClickRequest(app: "Calculator", elementIndex: 7)

        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.click(click)
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.performSecondaryAction(app: "Calculator", elementIndex: 7, action: "Show Menu")
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.setValue(app: "Calculator", elementIndex: 7, value: "42")
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.selectText(
            app: "Calculator",
            elementIndex: 7,
            text: "4",
            prefix: nil,
            suffix: "2",
            selectionType: .cursorAfter
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.scroll(app: "Calculator", elementIndex: 7, direction: .down, pages: 2)
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.drag(app: "Calculator", fromX: 1, fromY: 2, toX: 3, toY: 4)
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.pressKey(app: "Calculator", key: "Return")

        let calls = await fixture.actions.calls
        let waitCount = await fixture.settler.waitCount
        XCTAssertEqual(
            calls,
            [
                .click(click),
                .secondaryAction(index: 7, action: "Show Menu"),
                .setValue(index: 7, value: "42"),
                .selectText(
                    index: 7,
                    text: "4",
                    prefix: nil,
                    suffix: "2",
                    selectionType: .cursorAfter
                ),
                .scroll(index: 7, direction: .down, pages: 2),
                .drag(fromX: 1, fromY: 2, toX: 3, toY: 4),
                .pressKey("Return"),
            ]
        )
        XCTAssertEqual(waitCount, 7)
    }

    func testActionRejectsAReplacedWindowAndRequiresFreshState() async throws {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        await fixture.windows.replaceWindowID(with: 99)

        do {
            try await backend.typeText(app: "Calculator", text: "42")
            XCTFail("Expected stale observation")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .staleObservation("Calculator"))
        }
        let actionCalls = await fixture.actions.calls
        let waitCount = await fixture.settler.waitCount
        XCTAssertTrue(actionCalls.isEmpty)
        XCTAssertEqual(waitCount, 0)
    }

    func testCancellationAfterNativeActionSkipsSettling() async throws {
        let fixture = backendFixture(actionError: CancellationError())
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)

        await XCTAssertThrowsErrorAsync(
            try await backend.typeText(app: "Calculator", text: "42")
        )
        let waitCount = await fixture.settler.waitCount
        XCTAssertEqual(waitCount, 0)
    }
}

private struct BackendFixture {
    let applications: StubActionApplicationCatalog
    let windows: MutableActionWindowDiscovery
    let observations: StubComputerUseObserving
    let actions: RecordingComputerUseActions
    let settler: RecordingComputerUseSettler
}

private func backendFixture(actionError: Error? = nil) -> BackendFixture {
    let context = computerUseTestActionContext()
    let observation = ComputerUseObservation(
        target: context.target,
        state: ComputerUseAppState(app: "Calculator", screenshot: context.screenshot?.url, text: "0: AXWindow"),
        revision: context.revision,
        screenshot: context.screenshot
    )
    return BackendFixture(
        applications: StubActionApplicationCatalog(application: context.target.application),
        windows: MutableActionWindowDiscovery(window: context.target.window),
        observations: StubComputerUseObserving(observation: observation),
        actions: RecordingComputerUseActions(error: actionError),
        settler: RecordingComputerUseSettler()
    )
}

private actor StubActionApplicationCatalog: ComputerUseApplicationCatalogProviding {
    let application: ComputerUseApplicationRecord

    init(application: ComputerUseApplicationRecord) {
        self.application = application
    }

    func listApps() -> [ComputerUseApplication] {
        [application.publicApplication]
    }

    func resolveOrLaunch(_ identifier: String) -> ComputerUseApplicationRecord {
        application
    }
}

private actor MutableActionWindowDiscovery: ComputerUseWindowDiscovering {
    private var window: ComputerUseWindow

    init(window: ComputerUseWindow) {
        self.window = window
    }

    func orderedWindows(processIdentifier: Int32) -> [ComputerUseWindow] {
        [window]
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

private actor StubComputerUseObserving: ComputerUseObserving {
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

private actor ControllableComputerUseObserving: ComputerUseObserving {
    let observation: ComputerUseObservation
    private var shouldFail = false

    init(observation: ComputerUseObservation) {
        self.observation = observation
    }

    func failSubsequentObservations() {
        shouldFail = true
    }

    func observe(
        application: ComputerUseApplicationRecord,
        requestedIdentifier: String,
        disableDiff: Bool
    ) throws -> ComputerUseObservation {
        if shouldFail {
            throw ComputerUseObservationError.noWindow(requestedIdentifier)
        }
        return observation
    }
}

private actor RecordingComputerUseActions: ComputerUseActionServing {
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

private actor RecordingComputerUseSettler: ComputerUseActionSettling {
    private(set) var waitCount = 0

    func waitForUIToSettle() {
        waitCount += 1
    }
}
