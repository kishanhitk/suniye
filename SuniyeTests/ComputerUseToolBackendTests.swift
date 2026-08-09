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

    func testPhysicalInputAfterObservationRequiresARequery() async throws {
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

        do {
            try await backend.typeText(app: "Calculator", text: "42")
            XCTFail("Expected user intervention")
        } catch {
            XCTAssertEqual(error as? ComputerUseRuntimeError, .userIntervened)
        }

        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)
        try await backend.typeText(app: "Calculator", text: "42")
        let actionCalls = await fixture.actions.calls
        XCTAssertEqual(actionCalls, [.typeText("42")])
    }

    func testPhysicalInputDuringSettlingEndsTheActionAsIntervened() async throws {
        let fixture = backendFixture()
        let runtimeGuard = ControllableComputerUseRuntimeGuard()
        let settler = InterveningComputerUseSettler(runtimeGuard: runtimeGuard)
        let backend = ComputerUseToolBackend(
            applications: fixture.applications,
            windows: fixture.windows,
            observations: fixture.observations,
            actions: fixture.actions,
            settler: settler,
            runtimeGuard: runtimeGuard
        )
        _ = try await backend.getAppState(app: "Calculator", disableDiff: false)

        do {
            try await backend.typeText(app: "Calculator", text: "42")
            XCTFail("Expected user intervention")
        } catch {
            XCTAssertEqual(error as? ComputerUseRuntimeError, .userIntervened)
        }
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
