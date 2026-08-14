import CoreGraphics
import Foundation

struct ComputerUseCursorTarget: Equatable, Sendable {
    let windowID: UInt32
    let processIdentifier: Int32
}

enum ComputerUseCursorCoordinateSpace {
    static func appKitPoint(
        fromQuartz point: CGPoint,
        primaryScreenMaxY: CGFloat
    ) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }
}

enum ComputerUseCursorPresentation: Equatable, Sendable {
    case click(
        point: CGPoint,
        target: ComputerUseCursorTarget,
        mouseButton: ComputerUseMouseButton,
        clickCount: Int
    )
    case drag(
        from: CGPoint,
        to: CGPoint,
        target: ComputerUseCursorTarget
    )
    case scroll(
        point: CGPoint,
        target: ComputerUseCursorTarget,
        direction: ComputerUseScrollDirection,
        pages: Double
    )
}

protocol ComputerUseCursorPresenting: Sendable {
    func present(_ presentation: ComputerUseCursorPresentation) async throws
}

protocol ComputerUseCursorSessionManaging: Sendable {
    @MainActor
    func endSession()
}

struct NoopComputerUseCursorPresenter:
    ComputerUseCursorPresenting,
    ComputerUseCursorSessionManaging {
    func present(_ presentation: ComputerUseCursorPresentation) async throws {}
    @MainActor
    func endSession() {}
}

struct SystemComputerUseCursorPresenter:
    ComputerUseCursorPresenting,
    ComputerUseCursorSessionManaging {
    static let windowTitle = "Suniye Computer Use Cursor"

    func present(_ presentation: ComputerUseCursorPresentation) async throws {
        try await ComputerUseCursorOverlayController.shared.present(presentation)
    }

    @MainActor
    func endSession() {
        ComputerUseCursorOverlayController.shared.hide()
    }
}
