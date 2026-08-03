import CoreGraphics
import Foundation
import XCTest
@testable import Suniye

enum Phase2TestError: LocalizedError {
    case insertion

    var errorDescription: String? {
        "insert failed"
    }
}

final class Phase2StubInputEventPoster: ComputerUseInputEventPosting {
    struct KeyCall: Equatable {
        let key: ComputerUseKey
        let modifiers: ComputerUseKeyModifiers
    }

    struct ScrollCall: Equatable {
        let horizontal: Double
        let vertical: Double
    }

    struct DragCall: Equatable {
        let start: ComputerUsePoint
        let end: ComputerUsePoint
    }

    private(set) var clicks: [ComputerUsePoint] = []
    private(set) var keys: [KeyCall] = []
    private(set) var scrolls: [ScrollCall] = []
    private(set) var drags: [DragCall] = []
    var error: Error?

    func click(
        at point: ComputerUsePoint,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int,
        cancellation: ComputerUseCancellationToken
    ) throws {
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        clicks.append(contentsOf: repeatElement(point, count: clickCount))
    }

    func drag(
        from start: ComputerUsePoint,
        to end: ComputerUsePoint,
        cancellation: ComputerUseCancellationToken
    ) throws {
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        drags.append(DragCall(start: start, end: end))
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
        at point: ComputerUsePoint?,
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

final class Phase2StubValueActionPerformer: ComputerUseValueActionPerforming {
    struct SetValueCall: Equatable {
        let elementIndex: Int
        let value: String
    }

    struct SelectTextCall: Equatable {
        let elementIndex: Int
        let text: String
        let prefix: String?
        let suffix: String?
        let selectionType: ComputerUseTextSelectionType
    }

    private(set) var setValues: [SetValueCall] = []
    private(set) var selections: [SelectTextCall] = []

    func setValue(
        _ value: String,
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        setValues.append(SetValueCall(elementIndex: elementIndex, value: value))
    }

    func selectText(
        _ text: String,
        elementIndex: Int,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        selections.append(
            SelectTextCall(
                elementIndex: elementIndex,
                text: text,
                prefix: prefix,
                suffix: suffix,
                selectionType: selectionType
            )
        )
    }
}

final class Phase2StubTextInserter: TextInsertionServiceProtocol {
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

final class Phase2StubSemanticActionPerformer: ComputerUseSemanticActionPerforming {
    struct ActionCall: Equatable {
        let action: String
        let elementIndex: Int
    }

    private(set) var actions: [ActionCall] = []
    var error: Error?

    func perform(
        action: String,
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

final class Phase2StubPermissionManager: ComputerUsePermissionManaging {
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

final class Phase2StubWindowDiscovery: ComputerUseWindowDiscovering {
    var windows: [ComputerUseWindow]

    init(windows: [ComputerUseWindow]) {
        self.windows = windows
    }

    func listWindows(for application: ComputerUseApplication) -> [ComputerUseWindow] {
        windows
    }
}

final class Phase2StubWindowActivator: ComputerUseWindowActivating {
    private(set) var targets: [ComputerUseTarget] = []
    var result = true

    func activate(target: ComputerUseTarget) -> Bool {
        targets.append(target)
        return result
    }
}

final class Phase2StubApplicationCatalog: ComputerUseApplicationCatalog {
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

final class Phase2StubObservationService: ComputerUseObservationServicing {
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

final class Phase2StubActionService: ComputerUseActionServicing {
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

final class Phase2BlockingActionService: ComputerUseActionServicing {
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

func makePhase2Application() -> ComputerUseApplication {
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

func makePhase2Observation() -> ComputerUseObservation {
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

func makePhase2Grant(
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

func keyKey(_ action: ComputerUseAction) -> ComputerUseKey {
    guard case let .keyPress(key, _) = action else {
        XCTFail("Expected a key press action")
        return .named(.escape)
    }
    return key
}

func assertActionError(
    _ expected: ComputerUseActionError,
    operation: () throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        try operation()
        XCTFail("Expected \(expected), but the operation succeeded", file: file, line: line)
    } catch let error as ComputerUseActionError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected \(expected), got \(error)", file: file, line: line)
    }
}

@MainActor
func waitForPhase(
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
