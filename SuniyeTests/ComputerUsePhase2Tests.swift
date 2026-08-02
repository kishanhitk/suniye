import CoreGraphics
import Foundation
import XCTest
@testable import Suniye

final class ComputerUsePhase2ModelTests: XCTestCase {
    func testActionsRoundTripThroughCodableAndExposeSafeSummaries() throws {
        let modifiers = ComputerUseKeyModifiers(
            command: true,
            option: true,
            control: true,
            shift: true,
            function: true
        )
        let actions: [ComputerUseAction] = [
            .click(point: ComputerUsePoint(x: 12.5, y: 24.25)),
            .keyPress(key: .named(.returnKey), modifiers: modifiers),
            .keyPress(key: .character("a"), modifiers: ComputerUseKeyModifiers()),
            .scroll(horizontal: 4, vertical: -8),
            .typeText("secret text"),
            .semantic(elementIndex: 3, action: .press),
        ]

        for action in actions {
            let encoded = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(ComputerUseAction.self, from: encoded)
            XCTAssertEqual(decoded, action)
            XCTAssertFalse(action.summary.isEmpty)
        }

        XCTAssertEqual(actions[0].risk, .click)
        XCTAssertEqual(actions[1].risk, .keyPress)
        XCTAssertEqual(actions[2].risk, .keyPress)
        XCTAssertEqual(actions[3].risk, .scroll)
        XCTAssertEqual(actions[4].risk, .textEntry)
        XCTAssertEqual(actions[5].risk, .semanticAccessibility)
        XCTAssertEqual(actions[4].textPreview, "secret text")
        XCTAssertNil(actions[0].textPreview)

        XCTAssertEqual(ComputerUseKey.named(.forwardDelete).displayName, "Forward Delete")
        XCTAssertEqual(ComputerUseKey.character("a").displayName, "a")
        XCTAssertEqual(
            ComputerUseAction.keyPress(key: .named(.returnKey), modifiers: modifiers).summary,
            "Press Command + Option + Control + Shift + Function + Return"
        )
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskCommand))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskAlternate))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskControl))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskShift))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskSecondaryFn))
    }

    func testApprovalAndResultValuesRoundTripThroughCodable() throws {
        let observation = makePhase2Observation()
        let action = ComputerUseAction.typeText("hello")
        let request = ComputerUseApprovalRequest(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            action: action,
            target: observation.target,
            risk: action.risk,
            reason: "The user approved this exact text entry."
        )
        let grant = ComputerUseApprovalGrant(
            requestID: request.id,
            scope: .once,
            applicationID: observation.target.application.id,
            windowID: observation.target.window.id,
            observationGeneration: observation.generation,
            action: action
        )
        let result = ComputerUseActionResult(
            action: action,
            target: observation.target,
            completedAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseApprovalRequest.self,
                from: JSONEncoder().encode(request)
            ),
            request
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseApprovalGrant.self,
                from: JSONEncoder().encode(grant)
            ),
            grant
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseActionResult.self,
                from: JSONEncoder().encode(result)
            ),
            result
        )
        XCTAssertEqual(request.textPreview, "(5 characters hidden)")
        XCTAssertEqual(ComputerUseApprovalScope.once, .once)
        XCTAssertEqual(ComputerUseApprovalDecision.allowOnce, .allowOnce)
        XCTAssertEqual(ComputerUseApprovalDecision.deny, .deny)
        XCTAssertEqual(ComputerUseApprovalDecision.stopSession, .stopSession)
    }

    func testActionErrorsHaveUserFacingDescriptions() {
        let errors: [ComputerUseActionError] = [
            .cancelled,
            .approvalRequired,
            .staleApproval,
            .permissionRequired,
            .targetNotFrontmost,
            .invalidAction("bad bounds"),
            .unsupportedKey("?") ,
            .eventCreationFailed,
            .semanticActionFailed("AXPress"),
            .textInsertionFailed("clipboard unavailable"),
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}

final class ComputerUsePhase2PolicyTests: XCTestCase {
    func testPolicyAcceptsSupportedActionsFromTheObservation() throws {
        let observation = makePhase2Observation()

        let actions: [ComputerUseAction] = [
            .click(point: ComputerUsePoint(x: 100, y: 100)),
            .keyPress(key: .named(.returnKey), modifiers: ComputerUseKeyModifiers()),
            .keyPress(key: .character("a"), modifiers: ComputerUseKeyModifiers()),
            .scroll(horizontal: 0, vertical: -400),
            .typeText("hello"),
            .semantic(elementIndex: 0, action: .press),
            .semantic(elementIndex: 1, action: .increment),
        ]

        for action in actions {
            XCTAssertNoThrow(try ComputerUseActionPolicy.validate(action: action, observation: observation))
        }
    }

    func testPolicyRejectsOutOfBoundsAndNonFiniteClicks() {
        let observation = makePhase2Observation()

        assertActionError(.invalidAction("click must be inside the target window")) {
            try ComputerUseActionPolicy.validate(
                action: .click(point: ComputerUsePoint(x: 640.1, y: 100)),
                observation: observation
            )
        }
        assertActionError(.invalidAction("click must be inside the target window")) {
            try ComputerUseActionPolicy.validate(
                action: .click(point: ComputerUsePoint(x: .nan, y: 100)),
                observation: observation
            )
        }
    }

    func testPolicyRejectsInvalidKeysScrollTextAndSemanticActions() {
        let observation = makePhase2Observation()

        assertActionError(.invalidAction("character key must contain one character")) {
            try ComputerUseActionPolicy.validate(
                action: .keyPress(key: .character("ab"), modifiers: ComputerUseKeyModifiers()),
                observation: observation
            )
        }
        assertActionError(.invalidAction("scroll values exceed the allowed range")) {
            try ComputerUseActionPolicy.validate(
                action: .scroll(horizontal: 5_001, vertical: 0),
                observation: observation
            )
        }
        assertActionError(.invalidAction("scroll values exceed the allowed range")) {
            try ComputerUseActionPolicy.validate(
                action: .scroll(horizontal: .infinity, vertical: 0),
                observation: observation
            )
        }
        assertActionError(.invalidAction("text must contain between 1 and 10,000 characters")) {
            try ComputerUseActionPolicy.validate(
                action: .typeText(""),
                observation: observation
            )
        }
        assertActionError(.invalidAction("text must contain between 1 and 10,000 characters")) {
            try ComputerUseActionPolicy.validate(
                action: .typeText(String(repeating: "x", count: 10_001)),
                observation: observation
            )
        }
        assertActionError(.invalidAction("element index is not in the observation")) {
            try ComputerUseActionPolicy.validate(
                action: .semantic(elementIndex: 99, action: .press),
                observation: observation
            )
        }
        assertActionError(.invalidAction("the element does not expose AXPress")) {
            try ComputerUseActionPolicy.validate(
                action: .semantic(elementIndex: 1, action: .press),
                observation: observation
            )
        }

        let disabledElement = ComputerUseAXElement(
            index: 0,
            role: "AXButton",
            subrole: nil,
            title: "OK",
            description: nil,
            value: nil,
            isEnabled: false,
            isFocused: false,
            isSelected: false,
            bounds: nil,
            actions: ["AXPress"],
            childIndexes: []
        )
        let disabledObservation = ComputerUseObservation(
            generation: observation.generation,
            capturedAt: observation.capturedAt,
            target: observation.target,
            accessibility: ComputerUseAXSnapshot(
                text: "disabled",
                elements: [disabledElement],
                wasTruncated: false
            ),
            screenshot: nil
        )
        assertActionError(.invalidAction("the element is disabled")) {
            try ComputerUseActionPolicy.validate(
                action: .semantic(elementIndex: 0, action: .press),
                observation: disabledObservation
            )
        }
    }
}

final class ComputerUsePhase2ServiceTests: XCTestCase {
    func testActionServiceExecutesEachSupportedActionKind() throws {
        let observation = makePhase2Observation()
        let input = Phase2StubInputEventPoster()
        let text = Phase2StubTextInserter()
        let semantic = Phase2StubSemanticActionPerformer()
        let service = ComputerUseActionService(
            inputEventPoster: input,
            textInserter: text,
            semanticActionPerformer: semantic,
            targetValidator: Phase2StubTargetValidator(isCurrent: true),
            permissionManager: Phase2StubPermissionManager(granted: true),
            dateProvider: { Date(timeIntervalSince1970: 3_000) }
        )

        let click = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let key = ComputerUseAction.keyPress(
            key: .named(.returnKey),
            modifiers: ComputerUseKeyModifiers(command: true)
        )
        let scroll = ComputerUseAction.scroll(horizontal: 2, vertical: -400)
        let type = ComputerUseAction.typeText("hello")
        let semanticAction = ComputerUseAction.semantic(elementIndex: 0, action: .press)

        for action in [click, key, scroll, type, semanticAction] {
            let grant = makePhase2Grant(action: action, observation: observation)
            let result = try service.execute(
                action: action,
                observation: observation,
                approval: grant,
                requestID: grant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
            XCTAssertEqual(result.action, action)
            XCTAssertEqual(result.target, observation.target)
            XCTAssertEqual(result.completedAt, Date(timeIntervalSince1970: 3_000))
        }

        XCTAssertEqual(input.clicks, [ComputerUsePoint(x: 50, y: 50)])
        XCTAssertEqual(input.keys.count, 1)
        XCTAssertEqual(input.keys[0].key, keyKey(key))
        XCTAssertEqual(
            input.scrolls,
            [Phase2StubInputEventPoster.ScrollCall(horizontal: 2, vertical: -400)]
        )
        XCTAssertEqual(text.insertedTexts, ["hello"])
        XCTAssertEqual(
            semantic.actions,
            [Phase2StubSemanticActionPerformer.ActionCall(action: .press, elementIndex: 0)]
        )
    }

    func testActionServiceEnforcesApprovalPermissionAndCurrentTarget() {
        let observation = makePhase2Observation()
        let action = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let permission = Phase2StubPermissionManager(granted: true)
        let target = Phase2StubTargetValidator(isCurrent: true)
        let service = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: Phase2StubTextInserter(),
            semanticActionPerformer: Phase2StubSemanticActionPerformer(),
            targetValidator: target,
            permissionManager: permission
        )

        let staleGrant = ComputerUseApprovalGrant(
            requestID: UUID(),
            scope: .once,
            applicationID: observation.target.application.id,
            windowID: observation.target.window.id,
            observationGeneration: observation.generation + 1,
            action: action
        )
        assertActionError(.staleApproval) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: staleGrant,
                requestID: staleGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let mismatchedRequestGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.staleApproval) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: mismatchedRequestGrant,
                requestID: UUID(),
                cancellation: ComputerUseCancellationToken()
            )
        }

        permission.setGranted(false)
        let permissionGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.permissionRequired) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: permissionGrant,
                requestID: permissionGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        permission.setGranted(true)
        target.isCurrent = false
        let targetGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.targetNotFrontmost) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: targetGrant,
                requestID: targetGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let cancellation = ComputerUseCancellationToken()
        cancellation.cancel()
        let cancellationGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.cancelled) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: cancellationGrant,
                requestID: cancellationGrant.requestID,
                cancellation: cancellation
            )
        }
    }

    func testActionServiceMapsTextInsertionFailuresAndPropagatesNativeErrors() {
        let observation = makePhase2Observation()
        let text = Phase2StubTextInserter()
        text.insertError = Phase2TestError.insertion
        let service = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: text,
            semanticActionPerformer: Phase2StubSemanticActionPerformer(),
            targetValidator: Phase2StubTargetValidator(isCurrent: true),
            permissionManager: Phase2StubPermissionManager(granted: true)
        )
        let type = ComputerUseAction.typeText("hello")
        let textGrant = makePhase2Grant(action: type, observation: observation)

        assertActionError(.textInsertionFailed("insert failed")) {
            _ = try service.execute(
                action: type,
                observation: observation,
                approval: textGrant,
                requestID: textGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let input = Phase2StubInputEventPoster()
        input.error = ComputerUseActionError.eventCreationFailed
        let eventService = ComputerUseActionService(
            inputEventPoster: input,
            textInserter: Phase2StubTextInserter(),
            semanticActionPerformer: Phase2StubSemanticActionPerformer(),
            targetValidator: Phase2StubTargetValidator(isCurrent: true),
            permissionManager: Phase2StubPermissionManager(granted: true)
        )
        let click = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let eventGrant = makePhase2Grant(action: click, observation: observation)
        assertActionError(.eventCreationFailed) {
            _ = try eventService.execute(
                action: click,
                observation: observation,
                approval: eventGrant,
                requestID: eventGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }
    }

    func testTargetValidatorRequiresFrontmostProcessAndCurrentWindow() {
        let application = makePhase2Observation().target.application
        let window = makePhase2Observation().target.window
        let discovery = Phase2StubWindowDiscovery(windows: [window])
        var frontmostProcessIdentifier: Int32? = application.processIdentifier
        let validator = SystemComputerUseTargetValidator(
            windowDiscovery: discovery,
            frontmostProcessIdentifierProvider: { frontmostProcessIdentifier }
        )
        let target = ComputerUseTarget(application: application, window: window)

        XCTAssertTrue(validator.isCurrent(target: target))
        frontmostProcessIdentifier = 999
        XCTAssertFalse(validator.isCurrent(target: target))
        frontmostProcessIdentifier = application.processIdentifier
        discovery.windows = []
        XCTAssertFalse(validator.isCurrent(target: target))

        let nonKeyWindow = ComputerUseWindow(
            id: window.id,
            title: window.title,
            ownerProcessIdentifier: window.ownerProcessIdentifier,
            bounds: window.bounds,
            layer: window.layer,
            isOnScreen: window.isOnScreen,
            isKeyWindow: false
        )
        discovery.windows = [nonKeyWindow]
        XCTAssertFalse(validator.isCurrent(target: target))
    }
}

@MainActor
final class ComputerUsePhase2CoordinatorTests: XCTestCase {
    func testPhaseTitlesCoverTheActionStates() {
        let coordinator = makePhase2Coordinator(
            observation: makePhase2Observation(),
            actionService: Phase2StubActionService()
        )
        let expectedTitles: [(ComputerUseCoordinatorPhase, String)] = [
            (.requestingApproval, "Approval required"),
            (.acting, "Performing approved action"),
            (.actionCompleted, "Action completed"),
            (.actionFailed, "Action failed"),
        ]

        for (phase, title) in expectedTitles {
            coordinator.phase = phase
            XCTAssertEqual(coordinator.phaseTitle, title)
        }
    }

    func testApprovalFlowExecutesOnceAndRequiresFreshObservationForNextAction() async {
        let observation = makePhase2Observation()
        let actionService = Phase2StubActionService()
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)

        let action = ComputerUseAction.keyPress(
            key: .named(.returnKey),
            modifiers: ComputerUseKeyModifiers()
        )
        XCTAssertTrue(coordinator.canRequestAction)
        coordinator.requestAction(action)
        XCTAssertEqual(coordinator.phase, .requestingApproval)
        XCTAssertEqual(coordinator.pendingApproval?.action, action)
        XCTAssertFalse(coordinator.canRequestAction)

        coordinator.approvePendingAction()
        await waitForPhase(coordinator, .actionCompleted)

        XCTAssertEqual(actionService.executedActions, [action])
        XCTAssertEqual(coordinator.lastActionResult?.action, action)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertFalse(coordinator.canRequestAction)
    }

    func testDenyAndStopApprovalDoNotExecuteAndStopClearsObservation() async {
        let observation = makePhase2Observation()
        let actionService = Phase2StubActionService()
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)

        coordinator.requestAction(.scroll(horizontal: 0, vertical: -100))
        coordinator.denyPendingAction()
        XCTAssertEqual(coordinator.phase, .observed)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertTrue(actionService.executedActions.isEmpty)

        coordinator.requestAction(.typeText("hello"))
        coordinator.stopPendingAction()
        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertNil(coordinator.observation)
        XCTAssertTrue(actionService.executedActions.isEmpty)
    }

    func testInvalidActionAndActionFailureAreSurfacedWithoutPublishingAResult() async {
        let observation = makePhase2Observation()
        let actionService = Phase2StubActionService()
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)

        coordinator.requestAction(.click(point: ComputerUsePoint(x: 900, y: 900)))
        XCTAssertEqual(coordinator.phase, .actionFailed)
        XCTAssertEqual(
            coordinator.errorMessage,
            ComputerUseActionError.invalidAction("click must be inside the target window").errorDescription
        )
        XCTAssertNil(coordinator.pendingApproval)

        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)
        actionService.error = ComputerUseActionError.targetNotFrontmost
        coordinator.requestAction(.keyPress(key: .named(.escape), modifiers: ComputerUseKeyModifiers()))
        coordinator.approvePendingAction()
        await waitForPhase(coordinator, .actionFailed)

        XCTAssertEqual(coordinator.errorMessage, ComputerUseActionError.targetNotFrontmost.errorDescription)
        XCTAssertNil(coordinator.lastActionResult)
    }

    func testCancelStopsAnInFlightActionWithoutPublishingState() async {
        let observation = makePhase2Observation()
        let started = expectation(description: "action started")
        let actionService = Phase2BlockingActionService {
            started.fulfill()
        }
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)
        coordinator.requestAction(.keyPress(key: .named(.returnKey), modifiers: ComputerUseKeyModifiers()))
        coordinator.approvePendingAction()
        await fulfillment(of: [started], timeout: 1)

        coordinator.cancel()
        await waitForPhase(coordinator, .ready)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertNil(coordinator.lastActionResult)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(actionService.executeCount, 1)
    }

    private func makePhase2Coordinator(
        observation: ComputerUseObservation,
        actionService: ComputerUseActionServicing
    ) -> ComputerUseCoordinator {
        let application = observation.target.application
        return ComputerUseCoordinator(
            applicationCatalog: Phase2StubApplicationCatalog(applications: [application]),
            permissionManager: Phase2StubPermissionManager(granted: true),
            observationService: Phase2StubObservationService(result: observation),
            actionService: actionService
        )
    }
}

private enum Phase2TestError: LocalizedError {
    case insertion

    var errorDescription: String? {
        "insert failed"
    }
}

private final class Phase2StubInputEventPoster: ComputerUseInputEventPosting {
    struct KeyCall: Equatable {
        let key: ComputerUseKey
        let modifiers: ComputerUseKeyModifiers
    }

    struct ScrollCall: Equatable {
        let horizontal: Double
        let vertical: Double
    }

    private(set) var clicks: [ComputerUsePoint] = []
    private(set) var keys: [KeyCall] = []
    private(set) var scrolls: [ScrollCall] = []
    var error: Error?

    func click(at point: ComputerUsePoint, cancellation: ComputerUseCancellationToken) throws {
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        clicks.append(point)
    }

    func keyPress(
        key: ComputerUseKey,
        modifiers: ComputerUseKeyModifiers,
        cancellation: ComputerUseCancellationToken
    ) throws {
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        keys.append(KeyCall(key: key, modifiers: modifiers))
    }

    func scroll(
        horizontal: Double,
        vertical: Double,
        cancellation: ComputerUseCancellationToken
    ) throws {
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        scrolls.append(ScrollCall(horizontal: horizontal, vertical: vertical))
    }
}

private final class Phase2StubTextInserter: TextInsertionServiceProtocol {
    private(set) var insertedTexts: [String] = []
    var insertError: Error?

    func captureInsertionContext() -> TextInsertionContext? { nil }

    func insertText(_ text: String) throws {
        if let insertError {
            throw insertError
        }
        insertedTexts.append(text)
    }

    func copyTextToClipboard(_ text: String) throws {}

    func submitActiveInput() throws {}

    func makeFocusedFieldValueProvider() -> (() -> String?)? { nil }
}

private final class Phase2StubSemanticActionPerformer: ComputerUseSemanticActionPerforming {
    struct ActionCall: Equatable {
        let action: ComputerUseSemanticAction
        let elementIndex: Int
    }

    private(set) var actions: [ActionCall] = []
    var error: Error?

    func perform(
        action: ComputerUseSemanticAction,
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws {
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        actions.append(ActionCall(action: action, elementIndex: elementIndex))
    }
}

private final class Phase2StubTargetValidator: ComputerUseTargetValidating {
    var isCurrent: Bool

    init(isCurrent: Bool) {
        self.isCurrent = isCurrent
    }

    func isCurrent(target: ComputerUseTarget) -> Bool {
        isCurrent
    }
}

private final class Phase2StubPermissionManager: ComputerUsePermissionManaging {
    private var granted: Bool

    init(granted: Bool) {
        self.granted = granted
    }

    func snapshot() -> ComputerUsePermissionSnapshot {
        ComputerUsePermissionSnapshot(
            accessibility: granted ? .granted : .notGranted,
            screenRecording: .granted
        )
    }

    func setGranted(_ value: Bool) {
        granted = value
    }

    func requestAccessibility() -> Bool { true }

    func requestScreenRecording() -> Bool { true }
}

private final class Phase2StubWindowDiscovery: ComputerUseWindowDiscovering {
    var windows: [ComputerUseWindow]

    init(windows: [ComputerUseWindow]) {
        self.windows = windows
    }

    func listWindows(for application: ComputerUseApplication) -> [ComputerUseWindow] {
        windows
    }
}

private final class Phase2StubApplicationCatalog: ComputerUseApplicationCatalog {
    let applications: [ComputerUseApplication]

    init(applications: [ComputerUseApplication]) {
        self.applications = applications
    }

    func listApplications() -> [ComputerUseApplication] {
        applications
    }

    func application(withID identifier: String) -> ComputerUseApplication? {
        applications.first { $0.id == identifier }
    }
}

private final class Phase2StubObservationService: ComputerUseObservationServicing {
    let result: ComputerUseObservation

    init(result: ComputerUseObservation) {
        self.result = result
    }

    func observe(
        applicationID: String,
        includeScreenshot: Bool,
        configuration: ComputerUseObservationConfiguration,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        guard !cancellation.isCancelled else {
            throw ComputerUseObservationError.cancelled
        }
        return result
    }
}

private final class Phase2StubActionService: ComputerUseActionServicing {
    private(set) var executedActions: [ComputerUseAction] = []
    var error: Error?

    func execute(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approval: ComputerUseApprovalGrant,
        requestID: UUID,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseActionResult {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        if let error {
            throw error
        }
        executedActions.append(action)
        return ComputerUseActionResult(
            action: action,
            target: observation.target,
            completedAt: Date(timeIntervalSince1970: 4_000)
        )
    }
}

private final class Phase2BlockingActionService: ComputerUseActionServicing {
    let onStart: () -> Void
    private(set) var executeCount = 0

    init(onStart: @escaping () -> Void) {
        self.onStart = onStart
    }

    func execute(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approval: ComputerUseApprovalGrant,
        requestID: UUID,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseActionResult {
        executeCount += 1
        onStart()
        while !cancellation.isCancelled {
            Thread.sleep(forTimeInterval: 0.005)
        }
        throw ComputerUseActionError.cancelled
    }
}

private func makePhase2Application() -> ComputerUseApplication {
    ComputerUseApplication(
        id: "com.example.target#42",
        bundleIdentifier: "com.example.target",
        displayName: "Target App",
        processIdentifier: 42,
        isRunning: true,
        isActive: true,
        launchDate: nil
    )
}

private func makePhase2Observation() -> ComputerUseObservation {
    let application = makePhase2Application()
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
        generation: 1,
        capturedAt: Date(timeIntervalSince1970: 1_000),
        target: ComputerUseTarget(application: application, window: window),
        accessibility: ComputerUseAXSnapshot(
            text: "[0] role=AXButton title=OK\n[1] role=AXSlider title=Volume",
            elements: [
                ComputerUseAXElement(
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
                ),
                ComputerUseAXElement(
                    index: 1,
                    role: "AXSlider",
                    subrole: nil,
                    title: "Volume",
                    description: nil,
                    value: "50",
                    isEnabled: true,
                    isFocused: false,
                    isSelected: false,
                    bounds: ComputerUseRect(x: 40, y: 100, width: 200, height: 40),
                    actions: ["AXIncrement"],
                    childIndexes: []
                ),
            ],
            wasTruncated: false
        ),
        screenshot: nil
    )
}

private func makePhase2Grant(
    action: ComputerUseAction,
    observation: ComputerUseObservation
) -> ComputerUseApprovalGrant {
    ComputerUseApprovalGrant(
        requestID: UUID(),
        scope: .once,
        applicationID: observation.target.application.id,
        windowID: observation.target.window.id,
        observationGeneration: observation.generation,
        action: action
    )
}

private func keyKey(_ action: ComputerUseAction) -> ComputerUseKey {
    guard case let .keyPress(key, _) = action else {
        XCTFail("Expected a key press action")
        return .named(.escape)
    }
    return key
}

private func assertActionError(
    _ expected: ComputerUseActionError,
    operation: () throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        try operation()
        XCTFail("Expected (expected), but the operation succeeded", file: file, line: line)
    } catch let error as ComputerUseActionError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected (expected), got (error)", file: file, line: line)
    }
}

@MainActor
private func waitForPhase(
    _ coordinator: ComputerUseCoordinator,
    _ expected: ComputerUseCoordinatorPhase,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 {
        if coordinator.phase == expected {
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for phase \(expected), got \(coordinator.phase)", file: file, line: line)
}
