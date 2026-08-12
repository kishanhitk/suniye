import XCTest
@testable import Suniye

final class ComputerUseActionServiceTests: XCTestCase {
    func testMouseEventDescriptorTargetsObservedWindowUsingLocalCoordinates() {
        let descriptor = ComputerUseMouseEventDescriptor(
            screenPoint: CGPoint(x: 140, y: 90),
            windowID: 9,
            windowBounds: CGRect(x: 100, y: 50, width: 200, height: 100),
            windowUsesFlippedCoordinates: false
        )

        XCTAssertEqual(descriptor.eventLocation, CGPoint(x: 40, y: 40))
        XCTAssertEqual(descriptor.windowID, 9)
    }

    func testMouseEventDescriptorFlipsWindowLocalYCoordinateWhenRequired() {
        let descriptor = ComputerUseMouseEventDescriptor(
            screenPoint: CGPoint(x: 140, y: 90),
            windowID: 9,
            windowBounds: CGRect(x: 100, y: 50, width: 200, height: 100),
            windowUsesFlippedCoordinates: true
        )

        XCTAssertEqual(descriptor.eventLocation, CGPoint(x: 40, y: 60))
    }

    func testActionErrorsHaveUserReadableDescriptions() {
        let errors: [ComputerUseActionError] = [
            .observationRequired("Calculator"),
            .staleObservation("Calculator"),
            .elementUnavailable(7),
            .elementChanged,
            .elementDisabled,
            .actionUnavailable("AXPress"),
            .valueNotSettable,
            .textNotFound("hello"),
            .textAmbiguous("hello"),
            .screenshotUnavailable,
            .invalidArgument("Invalid value"),
            .eventCreationFailed,
            .unsupportedKey("Hyper"),
        ]

        for error in errors {
            XCTAssertFalse(try XCTUnwrap(error.errorDescription).isEmpty)
        }
    }

    func testIndexedClickPrefersAccessibilityPrimaryClick() async throws {
        let accessibility = RecordingAccessibilityActions(primaryClickResult: true)
        let input = RecordingInputEvents()
        let service = ComputerUseActionService(accessibility: accessibility, input: input)

        try await service.click(
            ComputerUseClickRequest(app: "Calculator", elementIndex: 7, clickCount: 2),
            context: computerUseTestActionContext()
        )

        let primaryClicks = await accessibility.primaryClicks
        let clicks = await input.clicks
        XCTAssertEqual(primaryClicks, [.init(index: 7, count: 2)])
        XCTAssertTrue(clicks.isEmpty)
    }

    func testIndexedClickPresentsVirtualCursorAtCurrentElementCenter() async throws {
        let cursor = RecordingComputerUseCursorPresenter()
        let service = ComputerUseActionService(
            accessibility: RecordingAccessibilityActions(
                primaryClickResult: true,
                center: CGPoint(x: 140, y: 90)
            ),
            input: RecordingInputEvents(),
            cursor: cursor
        )

        try await service.click(
            ComputerUseClickRequest(app: "Calculator", elementIndex: 7, clickCount: 2),
            context: computerUseTestActionContext()
        )

        let presentations = await cursor.presentations
        XCTAssertEqual(
            presentations,
            [
                .click(
                    point: CGPoint(x: 140, y: 90),
                    target: .init(windowID: 9, processIdentifier: 42),
                    mouseButton: .left,
                    clickCount: 2
                ),
            ]
        )
    }

    func testIndexedClickPropagatesCancellationWhileResolvingCursorPoint() async {
        let accessibility = RecordingAccessibilityActions(
            primaryClickResult: true,
            centerError: CancellationError()
        )
        let service = ComputerUseActionService(
            accessibility: accessibility,
            input: RecordingInputEvents(),
            cursor: RecordingComputerUseCursorPresenter()
        )

        await XCTAssertThrowsErrorAsync(
            try await service.click(
                ComputerUseClickRequest(app: "Calculator", elementIndex: 7),
                context: computerUseTestActionContext()
            )
        )

        let primaryClicks = await accessibility.primaryClicks
        XCTAssertTrue(primaryClicks.isEmpty)
    }

    func testIndexedClickFallsBackToProcessScopedEventAtCurrentElementCenter() async throws {
        let accessibility = RecordingAccessibilityActions(
            primaryClickResult: true,
            center: CGPoint(x: 140, y: 90)
        )
        let input = RecordingInputEvents()
        let service = ComputerUseActionService(accessibility: accessibility, input: input)

        try await service.click(
            ComputerUseClickRequest(
                app: "Calculator",
                elementIndex: 7,
                mouseButton: .right,
                clickCount: 2
            ),
            context: computerUseTestActionContext()
        )

        let clicks = await input.clicks
        let primaryClicks = await accessibility.primaryClicks
        XCTAssertTrue(primaryClicks.isEmpty)
        XCTAssertEqual(
            clicks,
            [
                .init(
                    point: CGPoint(x: 140, y: 90),
                    button: .right,
                    count: 2,
                    target: computerUseTestInputTarget()
                ),
            ]
        )
    }

    func testIndexedLeftClickFallsBackWhenNoSemanticClickActionIsAvailable() async throws {
        let accessibility = RecordingAccessibilityActions(
            primaryClickResult: false,
            center: CGPoint(x: 140, y: 90)
        )
        let input = RecordingInputEvents()
        let service = ComputerUseActionService(accessibility: accessibility, input: input)

        try await service.click(
            ComputerUseClickRequest(app: "Calculator", elementIndex: 7),
            context: computerUseTestActionContext()
        )

        let primaryClicks = await accessibility.primaryClicks
        let clicks = await input.clicks
        XCTAssertEqual(primaryClicks, [.init(index: 7, count: 1)])
        XCTAssertEqual(
            clicks,
            [
                .init(
                    point: CGPoint(x: 140, y: 90),
                    button: .left,
                    count: 1,
                    target: computerUseTestInputTarget()
                ),
            ]
        )
    }

    func testCoordinateActionsConvertScreenshotPixelsToScreenPoints() async throws {
        let input = RecordingInputEvents()
        let service = ComputerUseActionService(
            accessibility: RecordingAccessibilityActions(),
            input: input
        )
        let context = computerUseTestActionContext(
            screenshot: ComputerUseCapturedScreenshot(
                url: URL(fileURLWithPath: "/tmp/window.jpg"),
                pixelWidth: 400,
                pixelHeight: 200,
                coordinateScale: 0.5,
                windowFrame: CGRect(x: 100, y: 50, width: 200, height: 100)
            )
        )

        try await service.click(
            ComputerUseClickRequest(app: "Calculator", x: 80, y: 40),
            context: context
        )
        try await service.drag(
            fromX: 0,
            fromY: 0,
            toX: 400,
            toY: 200,
            context: context
        )

        let clicks = await input.clicks
        let drags = await input.drags
        XCTAssertEqual(clicks.first?.point, CGPoint(x: 140, y: 70))
        XCTAssertEqual(
            drags,
            [
                .init(
                    start: CGPoint(x: 100, y: 50),
                    end: CGPoint(x: 300, y: 150),
                    target: computerUseTestInputTarget()
                ),
            ]
        )
    }

    func testCoordinateClickPresentsVirtualCursorAtResolvedScreenPoint() async throws {
        let cursor = RecordingComputerUseCursorPresenter()
        let service = ComputerUseActionService(
            accessibility: RecordingAccessibilityActions(),
            input: RecordingInputEvents(),
            cursor: cursor
        )
        let context = computerUseTestActionContext(
            screenshot: ComputerUseCapturedScreenshot(
                url: URL(fileURLWithPath: "/tmp/window.jpg"),
                pixelWidth: 400,
                pixelHeight: 200,
                coordinateScale: 0.5,
                windowFrame: CGRect(x: 100, y: 50, width: 200, height: 100)
            )
        )

        try await service.click(
            ComputerUseClickRequest(app: "Calculator", x: 80, y: 40),
            context: context
        )

        let presentations = await cursor.presentations
        XCTAssertEqual(
            presentations,
            [
                .click(
                    point: CGPoint(x: 140, y: 70),
                    target: .init(windowID: 9, processIdentifier: 42),
                    mouseButton: .left,
                    clickCount: 1
                ),
            ]
        )
    }

    func testDragPresentsVirtualCursorAcrossResolvedScreenPoints() async throws {
        let cursor = RecordingComputerUseCursorPresenter()
        let service = ComputerUseActionService(
            accessibility: RecordingAccessibilityActions(),
            input: RecordingInputEvents(),
            cursor: cursor
        )
        let context = computerUseTestActionContext(
            screenshot: ComputerUseCapturedScreenshot(
                url: URL(fileURLWithPath: "/tmp/window.jpg"),
                pixelWidth: 400,
                pixelHeight: 200,
                coordinateScale: 0.5,
                windowFrame: CGRect(x: 100, y: 50, width: 200, height: 100)
            )
        )

        try await service.drag(
            fromX: 0,
            fromY: 0,
            toX: 400,
            toY: 200,
            context: context
        )

        let presentations = await cursor.presentations
        XCTAssertEqual(
            presentations,
            [
                .drag(
                    from: CGPoint(x: 100, y: 50),
                    to: CGPoint(x: 300, y: 150),
                    target: .init(windowID: 9, processIdentifier: 42)
                ),
            ]
        )
    }

    func testScrollPresentsVirtualCursorAtCurrentElementCenter() async throws {
        let cursor = RecordingComputerUseCursorPresenter()
        let service = ComputerUseActionService(
            accessibility: RecordingAccessibilityActions(center: CGPoint(x: 120, y: 80)),
            input: RecordingInputEvents(),
            cursor: cursor
        )

        try await service.scroll(
            elementIndex: 7,
            direction: .down,
            pages: 1.5,
            context: computerUseTestActionContext()
        )

        let presentations = await cursor.presentations
        XCTAssertEqual(
            presentations,
            [
                .scroll(
                    point: CGPoint(x: 120, y: 80),
                    target: .init(windowID: 9, processIdentifier: 42),
                    direction: .down,
                    pages: 1.5
                ),
            ]
        )
    }

    func testAccessibilityAndInputActionsForwardExactArguments() async throws {
        let accessibility = RecordingAccessibilityActions(center: CGPoint(x: 120, y: 80))
        let input = RecordingInputEvents()
        let service = ComputerUseActionService(accessibility: accessibility, input: input)
        let context = computerUseTestActionContext()

        try await service.performSecondaryAction("Show Menu", elementIndex: 7, context: context)
        try await service.setValue("42", elementIndex: 7, context: context)
        try await service.selectText(
            "world",
            elementIndex: 7,
            prefix: "hello ",
            suffix: "!",
            selectionType: .cursorAfter,
            context: context
        )
        try await service.scroll(
            elementIndex: 7,
            direction: .down,
            pages: 1.5,
            context: context
        )
        try await service.pressKey("Super_L+a", context: context)
        try await service.typeText("hello", context: context)

        let secondaryActions = await accessibility.secondaryActions
        let values = await accessibility.values
        let selections = await accessibility.selections
        let scrolls = await input.scrolls
        let keys = await input.keys
        let typedText = await input.typedText
        XCTAssertEqual(secondaryActions, [.init(index: 7, action: "Show Menu")])
        XCTAssertEqual(values, [.init(index: 7, value: "42")])
        XCTAssertEqual(
            selections,
            [.init(index: 7, text: "world", prefix: "hello ", suffix: "!", type: .cursorAfter)]
        )
        XCTAssertEqual(
            scrolls,
            [
                .init(
                    point: CGPoint(x: 120, y: 80),
                    direction: .down,
                    pages: 1.5,
                    target: computerUseTestInputTarget()
                ),
            ]
        )
        XCTAssertEqual(keys, [.init(chord: "Super_L+a", pid: 42)])
        XCTAssertEqual(typedText, [.init(text: "hello", pid: 42)])
    }

    func testRejectsOnlyInvalidPublicArguments() async {
        let service = ComputerUseActionService(
            accessibility: RecordingAccessibilityActions(),
            input: RecordingInputEvents()
        )
        let context = computerUseTestActionContext()

        await XCTAssertThrowsErrorAsync(
            try await service.click(
                ComputerUseClickRequest(app: "Calculator", x: .nan, y: 1),
                context: context
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await service.click(
                ComputerUseClickRequest(app: "Calculator", elementIndex: 7, clickCount: 0),
                context: context
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await service.scroll(
                elementIndex: 7,
                direction: .down,
                pages: 0,
                context: context
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await service.drag(
                fromX: 0,
                fromY: 0,
                toX: .infinity,
                toY: 1,
                context: context
            )
        )
        await XCTAssertThrowsErrorAsync(try await service.pressKey("   ", context: context))
    }

    func testRejectsMissingElementScreenshotAndProcess() async {
        let service = ComputerUseActionService(
            accessibility: RecordingAccessibilityActions(),
            input: RecordingInputEvents()
        )

        do {
            try await service.setValue(
                "42",
                elementIndex: 99,
                context: computerUseTestActionContext()
            )
            XCTFail("Expected a missing element error")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .elementUnavailable(99))
        }
        do {
            try await service.click(
                ComputerUseClickRequest(app: "Calculator", x: 1, y: 1),
                context: computerUseTestActionContext(screenshot: nil)
            )
            XCTFail("Expected a screenshot error")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .screenshotUnavailable)
        }
        do {
            try await service.typeText(
                "42",
                context: computerUseTestActionContext(processIdentifier: nil)
            )
            XCTFail("Expected a stale observation error")
        } catch {
            XCTAssertEqual(error as? ComputerUseActionError, .staleObservation("Calculator"))
        }
    }
}

func computerUseTestActionContext(
    processIdentifier: Int32? = 42,
    screenshot: ComputerUseCapturedScreenshot? = ComputerUseCapturedScreenshot(
        url: URL(fileURLWithPath: "/tmp/window.jpg"),
        pixelWidth: 200,
        pixelHeight: 100,
        coordinateScale: 1,
        windowFrame: CGRect(x: 100, y: 50, width: 200, height: 100)
    )
) -> ComputerUseActionContext {
    let application = ComputerUseApplicationRecord(
        displayName: "Calculator",
        bundleIdentifier: "com.apple.calculator",
        applicationURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
        lastUsedDate: nil,
        useCount: nil,
        processIdentifier: processIdentifier,
        isFrontmost: false
    )
    let window = ComputerUseWindow(
        id: 9,
        ownerProcessIdentifier: 42,
        title: "Calculator",
        bounds: CGRect(x: 100, y: 50, width: 200, height: 100),
        layer: 0,
        isOnScreen: true,
        accessibilityOrdinal: 0,
        isFocused: false,
        isMain: true
    )
    return ComputerUseActionContext(
        target: ComputerUseObservedTarget(application: application, window: window),
        revision: ComputerUseAccessibilityRevision(
            id: UUID(),
            text: "7: AXButton",
            elements: [
                7: ComputerUseAccessibilityElementReference(
                    rootIndex: 0,
                    path: [0],
                    role: "AXButton",
                    identifier: "equals"
                ),
            ]
        ),
        screenshot: screenshot
    )
}

private actor RecordingAccessibilityActions: ComputerUseAccessibilityActionPerforming {
    struct PrimaryClick: Equatable { let index: Int; let count: Int }
    struct Secondary: Equatable { let index: Int; let action: String }
    struct Value: Equatable { let index: Int; let value: String }
    struct Selection: Equatable {
        let index: Int
        let text: String
        let prefix: String?
        let suffix: String?
        let type: ComputerUseTextSelectionType
    }

    private let primaryClickResult: Bool
    private let resolvedCenter: CGPoint
    private let centerError: Error?
    private(set) var primaryClicks: [PrimaryClick] = []
    private(set) var secondaryActions: [Secondary] = []
    private(set) var values: [Value] = []
    private(set) var selections: [Selection] = []

    init(
        primaryClickResult: Bool = false,
        center: CGPoint = CGPoint(x: 0, y: 0),
        centerError: Error? = nil
    ) {
        self.primaryClickResult = primaryClickResult
        resolvedCenter = center
        self.centerError = centerError
    }

    func performPrimaryClick(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget,
        clickCount: Int
    ) -> Bool {
        primaryClicks.append(.init(index: index(for: reference), count: clickCount))
        return primaryClickResult
    }

    func center(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) throws -> CGPoint {
        if let centerError {
            throw centerError
        }
        return resolvedCenter
    }

    func perform(
        action: String,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) {
        secondaryActions.append(.init(index: index(for: reference), action: action))
    }

    func setValue(
        _ value: String,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) {
        values.append(.init(index: index(for: reference), value: value))
    }

    func selectText(
        _ text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) {
        selections.append(
            .init(
                index: index(for: reference),
                text: text,
                prefix: prefix,
                suffix: suffix,
                type: selectionType
            )
        )
    }

    private func index(for reference: ComputerUseAccessibilityElementReference) -> Int {
        reference.identifier == "equals" ? 7 : -1
    }
}

private actor RecordingInputEvents: ComputerUseInputEventPosting {
    struct Click: Equatable {
        let point: CGPoint
        let button: ComputerUseMouseButton
        let count: Int
        let target: ComputerUseInputEventTarget
    }
    struct Drag: Equatable {
        let start: CGPoint
        let end: CGPoint
        let target: ComputerUseInputEventTarget
    }
    struct Scroll: Equatable {
        let point: CGPoint
        let direction: ComputerUseScrollDirection
        let pages: Double
        let target: ComputerUseInputEventTarget
    }
    struct Key: Equatable { let chord: String; let pid: Int32 }
    struct Text: Equatable { let text: String; let pid: Int32 }

    private(set) var clicks: [Click] = []
    private(set) var drags: [Drag] = []
    private(set) var scrolls: [Scroll] = []
    private(set) var keys: [Key] = []
    private(set) var typedText: [Text] = []

    func click(
        at point: CGPoint,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int,
        target: ComputerUseInputEventTarget
    ) {
        clicks.append(.init(point: point, button: mouseButton, count: clickCount, target: target))
    }

    func drag(from start: CGPoint, to end: CGPoint, target: ComputerUseInputEventTarget) {
        drags.append(.init(start: start, end: end, target: target))
    }

    func scroll(
        at point: CGPoint,
        direction: ComputerUseScrollDirection,
        pages: Double,
        target: ComputerUseInputEventTarget
    ) {
        scrolls.append(.init(point: point, direction: direction, pages: pages, target: target))
    }

    func pressKey(_ chord: String, pid: Int32) {
        keys.append(.init(chord: chord, pid: pid))
    }

    func typeText(_ text: String, pid: Int32) {
        typedText.append(.init(text: text, pid: pid))
    }
}

private func computerUseTestInputTarget() -> ComputerUseInputEventTarget {
    ComputerUseInputEventTarget(
        processIdentifier: 42,
        windowID: 9,
        windowBounds: CGRect(x: 100, y: 50, width: 200, height: 100),
        windowUsesFlippedCoordinates: true
    )
}

private actor RecordingComputerUseCursorPresenter: ComputerUseCursorPresenting {
    private(set) var presentations: [ComputerUseCursorPresentation] = []

    func present(_ presentation: ComputerUseCursorPresentation) async throws {
        presentations.append(presentation)
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
