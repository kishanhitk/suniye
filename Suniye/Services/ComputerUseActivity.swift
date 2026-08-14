import Foundation

struct ComputerUseActivity: Codable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let arguments: String
    let output: String?
    /// The last observation a code-mode script made, carried so its screenshot
    /// can be reloaded and replayed when the conversation seeds a later run.
    let observedApp: String?
    let observedScreenshotURL: URL?

    init(
        id: UUID = UUID(),
        toolName: String,
        arguments: String,
        output: String? = nil,
        observedApp: String? = nil,
        observedScreenshotURL: URL? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.output = output
        self.observedApp = observedApp
        self.observedScreenshotURL = observedScreenshotURL
    }

    func completed(
        output: String,
        observedApp: String? = nil,
        observedScreenshotURL: URL? = nil
    ) -> ComputerUseActivity {
        ComputerUseActivity(
            id: id,
            toolName: toolName,
            arguments: arguments,
            output: output,
            observedApp: observedApp,
            observedScreenshotURL: observedScreenshotURL
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
