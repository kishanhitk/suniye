import Foundation

struct ComputerUseActivity: Equatable, Sendable {
    let toolName: String
    let arguments: String
}

struct ComputerUseActivitySink: Sendable {
    private let handler: @Sendable (ComputerUseActivity) async -> Void

    init(handler: @escaping @Sendable (ComputerUseActivity) async -> Void) {
        self.handler = handler
    }

    func emit(_ activity: ComputerUseActivity) async {
        await handler(activity)
    }

    static let disabled = ComputerUseActivitySink { _ in }
}
