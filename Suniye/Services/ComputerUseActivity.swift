import Foundation

struct ComputerUseActivity: Codable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let arguments: String
    let output: String?

    init(
        id: UUID = UUID(),
        toolName: String,
        arguments: String,
        output: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.output = output
    }

    func completed(output: String) -> ComputerUseActivity {
        ComputerUseActivity(
            id: id,
            toolName: toolName,
            arguments: arguments,
            output: output
        )
    }
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
