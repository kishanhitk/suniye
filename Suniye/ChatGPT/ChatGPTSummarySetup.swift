import Foundation
import Observation
import SuniyeAnalytics

/// The state and the actions of the ChatGPT sheet in Settings: connect,
/// disconnect, and the model for summaries.
@MainActor
@Observable
final class ChatGPTSummarySetup {
    private(set) var state = ChatGPTConnection.State.notConnected
    /// The browser has the sign-in page and the app waits for its return.
    private(set) var isWaitingForSignIn = false
    private(set) var message: String?
    /// Empty until the list loads, and when it cannot load.
    private(set) var models: [ChatGPTModel] = []

    @ObservationIgnored private let connection: ChatGPTConnection
    @ObservationIgnored private let client: ChatGPTPlanClient
    @ObservationIgnored private let meetings: MeetingCoordinator
    @ObservationIgnored private let analytics: Analytics
    @ObservationIgnored private var signIn: Task<Void, Never>?

    init(connection: ChatGPTConnection, client: ChatGPTPlanClient, meetings: MeetingCoordinator, analytics: Analytics) {
        self.connection = connection
        self.client = client
        self.meetings = meetings
        self.analytics = analytics
    }

    /// The model that summaries use: the saved one, else the default.
    var model: String {
        meetings.settings.chatGPTModel ?? ChatGPTPlanClient.defaultModel
    }

    /// Call when the sheet opens.
    func open() async {
        message = nil
        await client.endPause()
        state = await connection.state()
        await loadModels()
    }

    func connect() {
        guard signIn == nil else { return }
        message = nil
        isWaitingForSignIn = true
        signIn = Task {
            let outcome = await connection.connect()
            analytics.track(.chatGPTSignIn(outcome: outcome))
            state = await connection.state()
            isWaitingForSignIn = false
            signIn = nil
            message = Self.message(for: outcome)
            if outcome == .connected {
                meetings.updateSettings { $0.summaryModel = .chatGPT }
                await loadModels()
            }
        }
    }

    func cancelSignIn() {
        signIn?.cancel()
    }

    /// No summary uses ChatGPT from the first step on: a summary that the
    /// cancel stops must not start again with ChatGPT.
    func disconnect() async {
        meetings.stopUsingChatGPT()
        let confirmed = await connection.disconnect()
        state = await connection.state()
        models = []
        message = confirmed ? nil : "Disconnected on this Mac. To remove the access, open ChatGPT Settings > Security and login > Sign in with ChatGPT."
    }

    func useChatGPT() {
        meetings.updateSettings { $0.summaryModel = .chatGPT }
    }

    func choose(model slug: String) {
        meetings.updateSettings { $0.chatGPTModel = slug }
    }

    /// A saved model that the account does not list any more gives way to
    /// the default model, or to the first one of the list.
    private func loadModels() async {
        guard case .connected = state, let listed = try? await client.models(), !listed.isEmpty else {
            models = []
            return
        }
        models = listed
        if !listed.contains(where: { $0.slug == model }) {
            choose(model: listed.first { $0.slug == ChatGPTPlanClient.defaultModel }?.slug ?? listed[0].slug)
        }
    }

    private static func message(for outcome: ChatGPTSignInOutcome) -> String? {
        switch outcome {
        case .connected, .canceled:
            return nil
        case .denied:
            return "ChatGPT sign-in was canceled."
        case .noPlanPermission:
            return "This ChatGPT account did not allow plan use. Summaries need it."
        case .timedOut:
            return "ChatGPT sign-in timed out."
        case .failed:
            return "ChatGPT sign-in did not finish."
        }
    }
}
