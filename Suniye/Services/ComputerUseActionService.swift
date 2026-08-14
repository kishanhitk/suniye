import CoreGraphics
import Foundation

struct ComputerUseActionContext: Equatable, Sendable {
    let target: ComputerUseObservedTarget
    let revision: ComputerUseAccessibilityRevision
    let screenshot: ComputerUseCapturedScreenshot?
}

enum ComputerUseActionError: LocalizedError, Equatable, Sendable {
    case observationRequired(String)
    case staleObservation(String)
    case elementUnavailable(Int)
    case elementChanged
    case elementDisabled
    case actionUnavailable(String)
    case valueNotSettable
    case textNotFound(String)
    case textAmbiguous(String)
    case screenshotUnavailable
    case invalidArgument(String)
    case eventCreationFailed
    case unsupportedKey(String)

    var errorDescription: String? {
        switch self {
        case let .observationRequired(app):
            "Observe \(app) before performing an action."
        case let .staleObservation(app):
            "The observed window for \(app) changed. Observe it again before acting."
        case let .elementUnavailable(index):
            "Accessibility element \(index) is no longer available."
        case .elementChanged:
            "The Accessibility element changed. Observe the application again before acting."
        case .elementDisabled:
            "The Accessibility element is disabled."
        case let .actionUnavailable(action):
            "Accessibility action \(action) is not available."
        case .valueNotSettable:
            "The Accessibility element does not accept a replacement value."
        case let .textNotFound(text):
            "The requested text was not found: \(text)."
        case let .textAmbiguous(text):
            "The requested text is ambiguous: \(text)."
        case .screenshotUnavailable:
            "A current window screenshot is required for coordinate input."
        case let .invalidArgument(message):
            message
        case .eventCreationFailed:
            "macOS could not create the input event."
        case let .unsupportedKey(key):
            "The key is not supported: \(key)."
        }
    }
}

protocol ComputerUseAccessibilityActionPerforming: Sendable {
    func performPrimaryClick(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget,
        clickCount: Int
    ) async throws -> Bool
    func center(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws -> CGPoint
    func perform(
        action: String,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws
    func setValue(
        _ value: String,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws
    func selectText(
        _ text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws
}

protocol ComputerUseInputEventPosting: Sendable {
    func click(
        at point: CGPoint,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int,
        target: ComputerUseInputEventTarget
    ) async throws
    func drag(
        from start: CGPoint,
        to end: CGPoint,
        target: ComputerUseInputEventTarget
    ) async throws
    func scroll(
        at point: CGPoint,
        direction: ComputerUseScrollDirection,
        pages: Double,
        target: ComputerUseInputEventTarget
    ) async throws
    func pressKey(_ chord: String, pid: Int32) async throws
    func typeText(_ text: String, pid: Int32) async throws
}

protocol ComputerUseFocusEnforcing: Sendable {
    func focusForKeyInput(target: ComputerUseObservedTarget) async throws
}

protocol ComputerUseActionServing: Sendable {
    func click(_ request: ComputerUseClickRequest, context: ComputerUseActionContext) async throws
    func performSecondaryAction(
        _ action: String,
        elementIndex: Int,
        context: ComputerUseActionContext
    ) async throws
    func setValue(
        _ value: String,
        elementIndex: Int,
        context: ComputerUseActionContext
    ) async throws
    func selectText(
        _ text: String,
        elementIndex: Int,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        context: ComputerUseActionContext
    ) async throws
    func scroll(
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double,
        context: ComputerUseActionContext
    ) async throws
    func drag(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        context: ComputerUseActionContext
    ) async throws
    func pressKey(_ key: String, context: ComputerUseActionContext) async throws
    func typeText(_ text: String, context: ComputerUseActionContext) async throws
}

struct ComputerUseActionService: ComputerUseActionServing {
    private let accessibility: ComputerUseAccessibilityActionPerforming
    private let input: ComputerUseInputEventPosting
    private let cursor: ComputerUseCursorPresenting
    private let focus: ComputerUseFocusEnforcing

    init(
        accessibility: ComputerUseAccessibilityActionPerforming =
            SystemComputerUseAccessibilityActions(),
        input: ComputerUseInputEventPosting = SystemComputerUseInputEvents(),
        cursor: ComputerUseCursorPresenting = NoopComputerUseCursorPresenter(),
        focus: ComputerUseFocusEnforcing = SystemComputerUseFocusEnforcer()
    ) {
        self.accessibility = accessibility
        self.input = input
        self.cursor = cursor
        self.focus = focus
    }

    func click(_ request: ComputerUseClickRequest, context: ComputerUseActionContext) async throws {
        // The model supplies click_count; triple-click is the largest gesture
        // macOS recognizes, and an unbounded count drives an unbounded event loop.
        guard (1...3).contains(request.clickCount) else {
            throw ComputerUseActionError.invalidArgument("click_count must be between 1 and 3")
        }
        let pid = try processIdentifier(context)
        switch request.target {
        case let .element(index):
            let reference = try element(index, in: context)
            // A center() failure is held, not thrown: the AX-only click below
            // can still succeed without a screen point. It resurfaces only if
            // synthetic input ends up needing that point.
            let centerResult: Result<CGPoint, Error>
            do {
                centerResult = .success(
                    try await accessibility.center(reference: reference, target: context.target)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                centerResult = .failure(error)
            }
            if case let .success(cursorPoint) = centerResult {
                try await presentClick(
                    request,
                    at: cursorPoint,
                    processIdentifier: pid,
                    context: context
                )
            }
            if request.mouseButton == .left,
               try await accessibility.performPrimaryClick(
                   reference: reference,
                   target: context.target,
                   clickCount: request.clickCount
               ) {
                return
            }
            try await input.click(
                at: centerResult.get(),
                mouseButton: request.mouseButton,
                clickCount: request.clickCount,
                target: inputTarget(context, processIdentifier: pid)
            )
        case let .coordinates(x, y):
            try requireFinite([x, y], name: "click coordinates")
            let point = try screenPoint(x: x, y: y, context: context)
            try await presentClick(
                request,
                at: point,
                processIdentifier: pid,
                context: context
            )
            try await input.click(
                at: point,
                mouseButton: request.mouseButton,
                clickCount: request.clickCount,
                target: inputTarget(context, processIdentifier: pid)
            )
        }
    }

    func performSecondaryAction(
        _ action: String,
        elementIndex: Int,
        context: ComputerUseActionContext
    ) async throws {
        try await accessibility.perform(
            action: action,
            reference: element(elementIndex, in: context),
            target: context.target
        )
    }

    func setValue(
        _ value: String,
        elementIndex: Int,
        context: ComputerUseActionContext
    ) async throws {
        try await accessibility.setValue(
            value,
            reference: element(elementIndex, in: context),
            target: context.target
        )
    }

    func selectText(
        _ text: String,
        elementIndex: Int,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        context: ComputerUseActionContext
    ) async throws {
        try await accessibility.selectText(
            text,
            prefix: prefix,
            suffix: suffix,
            selectionType: selectionType,
            reference: element(elementIndex, in: context),
            target: context.target
        )
    }

    func scroll(
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double,
        context: ComputerUseActionContext
    ) async throws {
        guard pages.isFinite, pages > 0 else {
            throw ComputerUseActionError.invalidArgument("pages must be a finite number greater than zero")
        }
        let reference = try element(elementIndex, in: context)
        let point = try await accessibility.center(reference: reference, target: context.target)
        let processIdentifier = try processIdentifier(context)
        try await cursor.present(
            .scroll(
                point: point,
                target: ComputerUseCursorTarget(
                    windowID: context.target.window.id,
                    processIdentifier: processIdentifier
                ),
                direction: direction,
                pages: pages
            )
        )
        try await input.scroll(
            at: point,
            direction: direction,
            pages: pages,
            target: inputTarget(context, processIdentifier: processIdentifier)
        )
    }

    func drag(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        context: ComputerUseActionContext
    ) async throws {
        try requireFinite([fromX, fromY, toX, toY], name: "drag coordinates")
        let processIdentifier = try processIdentifier(context)
        let start = try screenPoint(x: fromX, y: fromY, context: context)
        let end = try screenPoint(x: toX, y: toY, context: context)
        try await cursor.present(
            .drag(
                from: start,
                to: end,
                target: ComputerUseCursorTarget(
                    windowID: context.target.window.id,
                    processIdentifier: processIdentifier
                )
            )
        )
        try await input.drag(
            from: start,
            to: end,
            target: inputTarget(context, processIdentifier: processIdentifier)
        )
    }

    func pressKey(_ key: String, context: ComputerUseActionContext) async throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComputerUseActionError.invalidArgument("key is required")
        }
        let pid = try processIdentifier(context)
        try await focus.focusForKeyInput(target: context.target)
        try await input.pressKey(key, pid: pid)
    }

    func typeText(_ text: String, context: ComputerUseActionContext) async throws {
        let pid = try processIdentifier(context)
        try await focus.focusForKeyInput(target: context.target)
        try await input.typeText(text, pid: pid)
    }

    private func element(
        _ index: Int,
        in context: ComputerUseActionContext
    ) throws -> ComputerUseAccessibilityElementReference {
        guard let reference = context.revision.elements[index] else {
            throw ComputerUseActionError.elementUnavailable(index)
        }
        return reference
    }

    private func processIdentifier(_ context: ComputerUseActionContext) throws -> Int32 {
        guard let pid = context.target.application.processIdentifier else {
            throw ComputerUseActionError.staleObservation(context.target.application.displayName)
        }
        return pid
    }

    private func presentClick(
        _ request: ComputerUseClickRequest,
        at point: CGPoint,
        processIdentifier: Int32,
        context: ComputerUseActionContext
    ) async throws {
        try await cursor.present(
            .click(
                point: point,
                target: ComputerUseCursorTarget(
                    windowID: context.target.window.id,
                    processIdentifier: processIdentifier
                ),
                mouseButton: request.mouseButton,
                clickCount: request.clickCount
            )
        )
    }

    private func inputTarget(
        _ context: ComputerUseActionContext,
        processIdentifier: Int32
    ) -> ComputerUseInputEventTarget {
        ComputerUseInputEventTarget(
            processIdentifier: processIdentifier,
            windowID: context.target.window.id,
            windowBounds: context.target.window.bounds
        )
    }

    private func screenPoint(
        x: Double,
        y: Double,
        context: ComputerUseActionContext
    ) throws -> CGPoint {
        guard let screenshot = context.screenshot,
              screenshot.pixelWidth > 0,
              screenshot.pixelHeight > 0 else {
            throw ComputerUseActionError.screenshotUnavailable
        }
        // Coordinates are screenshot-relative; anything outside its pixel
        // bounds would map onto an arbitrary point of another window.
        guard (0...Double(screenshot.pixelWidth)).contains(x),
              (0...Double(screenshot.pixelHeight)).contains(y) else {
            throw ComputerUseActionError.invalidArgument(
                "coordinates must be within the observed screenshot (\(screenshot.pixelWidth)x\(screenshot.pixelHeight))"
            )
        }
        return CGPoint(
            x: screenshot.windowFrame.minX + x * screenshot.coordinateScale,
            y: screenshot.windowFrame.minY + y * screenshot.coordinateScale
        )
    }

    private func requireFinite(_ values: [Double], name: String) throws {
        guard values.allSatisfy(\.isFinite) else {
            throw ComputerUseActionError.invalidArgument("\(name) must be finite")
        }
    }
}
