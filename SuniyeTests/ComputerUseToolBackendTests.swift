import XCTest
@testable import Suniye

final class ComputerUseToolBackendTests: XCTestCase {
    func testDefaultBackendCanBeConstructedWithoutStartingSystemWork() {
        _ = ComputerUseToolBackend()
    }

    func testSystemSettlerIsCancellationAware() async {
        let task = Task {
            try await SystemComputerUseActionSettler().waitForUIToSettle(
                target: computerUseTestActionContext().target
            )
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
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
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
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
        )

        let state = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.typeText(app: "Calculator", text: "42")

        let actionCalls = await fixture.actions.calls
        let waitCount = await fixture.settler.waitCount
        XCTAssertEqual(state.text, "0: AXWindow")
        XCTAssertEqual(actionCalls, [.typeText("42")])
        XCTAssertEqual(waitCount, 1)
    }

    func testObservationWaitsForReplacementWindowInTheSameRunningProcess() async throws {
        let fixture = backendFixture()
        let observations = ControllableComputerUseObserving(observation: fixture.observations.observation)
        await observations.failNextObservation()
        await fixture.windows.hideForNextCalls(1)
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard,
            windowReacquisitionTimeout: .seconds(1),
            windowReacquisitionPollingInterval: .milliseconds(1)
        )

        let state = try await backend.getAppState(app: "Calculator", disableDiff: false)

        XCTAssertEqual(state.text, "0: AXWindow")
        let callCount = await fixture.windows.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testObservationReportsLaunchFailureWhenRunningApplicationCannotReopen() async {
        let fixture = backendFixture()
        let observations = ControllableComputerUseObserving(observation: fixture.observations.observation)
        await observations.failNextObservation()
        await fixture.windows.hideForNextCalls(1)
        await fixture.applications.failReopen(
            with: ComputerUseApplicationCatalogError.launchFailed("Calculator")
        )
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard,
            windowReacquisitionTimeout: .zero,
            windowReacquisitionPollingInterval: .milliseconds(1)
        )

        do {
            _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
            XCTFail("Expected launch failure")
        } catch {
            XCTAssertEqual(
                error as? ComputerUseApplicationCatalogError,
                .launchFailed("Calculator")
            )
        }
    }

    func testObservationReopensRunningApplicationWhenNoWindowAppears() async throws {
        let fixture = backendFixture()
        let observations = ControllableComputerUseObserving(observation: fixture.observations.observation)
        await observations.failNextObservation()
        await fixture.windows.hideForNextCalls(1)
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard,
            windowReacquisitionTimeout: .zero,
            windowReacquisitionPollingInterval: .milliseconds(1)
        )

        let state = try await backend.getAppState(app: "Calculator", disableDiff: false)

        XCTAssertEqual(state.text, "0: AXWindow")
        let reopenCount = await fixture.applications.reopenCount
        XCTAssertEqual(reopenCount, 1)
    }

    func testActionRequiresAReferenceObservation() async {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
        )

        do {
            try await backend.pressKey(app: "Calculator", key: "Return")
            XCTFail("Expected an observation-required error")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .observationRequired("Calculator"))
        }
    }

    func testSuccessfulActionRequiresAFreshObservationForTheNextAction() async throws {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.typeText(app: "Calculator", text: "42")

        do {
            try await backend.pressKey(app: "Calculator", key: "Return")
            XCTFail("Expected a new observation before the next action")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .observationRequired("Calculator"))
        }

        let calls = await fixture.actions.calls
        XCTAssertEqual(calls, [.typeText("42")])
    }

    func testFailedRefreshInvalidatesThePreviousObservation() async throws {
        let fixture = backendFixture()
        let observations = ControllableComputerUseObserving(observation: fixture.observations.observation)
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
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

    func testForwardsEveryActionKindAfterItsOwnFreshObservation() async throws {
        let fixture = backendFixture()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
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
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
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
            settler: fixture.settler,
            runtimeGuard: fixture.runtimeGuard
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)

        await XCTAssertThrowsErrorAsync(
            try await backend.typeText(app: "Calculator", text: "42")
        )
        let waitCount = await fixture.settler.waitCount
        XCTAssertEqual(waitCount, 0)
    }

    func testLockedScreenRejectsObservationBeforeNativeCapture() async {
        let fixture = backendFixture()
        let runtimeGuard = ControllableComputerUseRuntimeGuard(isScreenLocked: true)
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: runtimeGuard
        )

        do {
            _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
            XCTFail("Expected a screen-locked error")
        } catch {
            XCTAssertEqual(error as? ComputerUseRuntimeError, .screenLocked)
        }
        let observationCount = await runtimeGuard.observationCount
        XCTAssertEqual(observationCount, 0)
    }

    func testPhysicalInputAfterObservationDoesNotCancelTheAction() async throws {
        let fixture = backendFixture()
        let runtimeGuard = ControllableComputerUseRuntimeGuard()
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: fixture.settler,
            runtimeGuard: runtimeGuard
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        await runtimeGuard.recordPhysicalInput()

        try await backend.typeText(app: "Calculator", text: "42")
        let actionCalls = await fixture.actions.calls
        XCTAssertEqual(actionCalls, [.typeText("42")])
    }

    func testSettlerExtendsDelayOnlyWhileLoadingIndicatorIsPresent() async throws {
        let loading = ScriptedComputerUseLoadingState(states: [true, true, false])
        let sleeper = RecordingComputerUseSleeper()
        let settler = SystemComputerUseActionSettler(
            loadingState: loading,
            sleeper: sleeper,
            initialDelay: .seconds(1),
            loadingPollDelay: .milliseconds(500),
            maximumLoadingChecks: 10
        )

        try await settler.waitForUIToSettle(target: computerUseTestActionContext().target)

        let delays = await sleeper.delays
        let checkCount = await loading.checkCount
        XCTAssertEqual(delays, [.seconds(1), .milliseconds(500), .milliseconds(500)])
        XCTAssertEqual(checkCount, 3)
    }
}
