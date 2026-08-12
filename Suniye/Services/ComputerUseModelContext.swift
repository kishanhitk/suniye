import Foundation

struct ComputerUseModelContextPolicy: Equatable, Sendable {
    let maximumMessages: Int
    let maximumContextTokens: Int
    let maximumToolOutputTokens: Int
    let maximumScreenshots: Int

    static func referenceAligned(modelID: String) -> Self {
        let isLuna = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "gpt-5.6-luna"
        return Self(
            maximumMessages: 50,
            maximumContextTokens: isLuna ? 272_000 : 100_000,
            maximumToolOutputTokens: isLuna ? 10_000 : 2_500,
            maximumScreenshots: 2
        )
    }
}

struct ComputerUseModelContextBuilder: Sendable {
    let policy: ComputerUseModelContextPolicy

    init(policy: ComputerUseModelContextPolicy = .referenceAligned(modelID: "")) {
        self.policy = policy
    }

    func initialMessages(
        conversation: [ComputerUseConversationMessage],
        instruction: String,
        screenshots: any ComputerUseScreenshotLoading
    ) async -> [ComputerUseModelMessage] {
        let screenshotReferences = conversation.enumerated().compactMap { index, message in
            persistedScreenshotReference(for: message).map { (index, $0) }
        }
        var loadedScreenshots: [Int: (PersistedScreenshotReference, String)] = [:]
        for (index, reference) in screenshotReferences.reversed() {
            guard loadedScreenshots.count < policy.maximumScreenshots else { break }
            guard let dataURL = try? await screenshots.dataURL(for: reference.url) else {
                continue
            }
            loadedScreenshots[index] = (reference, dataURL)
        }
        var messages: [ComputerUseModelMessage] = []
        for (index, message) in conversation.enumerated() {
            messages.append(contentsOf: normalize(message))
            guard let (reference, dataURL) = loadedScreenshots[index] else {
                continue
            }
            messages.append(
                .image(
                    role: .user,
                    text: "Current \(reference.app) screenshot.",
                    dataURL: dataURL
                )
            )
        }
        messages.append(.text(role: .user, text: instruction))
        return compact(messages, currentInstruction: instruction)
    }

    func compact(
        _ messages: [ComputerUseModelMessage],
        currentInstruction: String
    ) -> [ComputerUseModelMessage] {
        let screenshotIndexes = messages.indices.filter { messages[$0].isImage }
        let retainedScreenshotIndexes = Set(screenshotIndexes.suffix(policy.maximumScreenshots))
        let filtered = messages.enumerated().compactMap { index, message in
            message.isImage && !retainedScreenshotIndexes.contains(index) ? nil : message
        }
        let groups = groupProtocolMessages(filtered)
        let currentInstructionGroup = groups.lastIndex { group in
            group.messages.contains {
                $0.role == .user && $0.textContent == currentInstruction
            }
        }
        let latestObservationGroup = groups.lastIndex(where: \.isObservation)
        let mandatory = Set([currentInstructionGroup, latestObservationGroup].compactMap { $0 })
        var selected = mandatory
        var messageCount = mandatory.reduce(0) { $0 + groups[$1].messages.count }
        var tokenCount = mandatory.reduce(0) { $0 + groups[$1].tokenCount }

        for index in groups.indices.reversed() where !selected.contains(index) {
            let group = groups[index]
            guard messageCount + group.messages.count <= policy.maximumMessages,
                  tokenCount + group.tokenCount <= policy.maximumContextTokens else {
                continue
            }
            selected.insert(index)
            messageCount += group.messages.count
            tokenCount += group.tokenCount
        }

        return groups.indices
            .filter(selected.contains)
            .flatMap { groups[$0].messages }
    }

    private func normalize(
        _ message: ComputerUseConversationMessage
    ) -> [ComputerUseModelMessage] {
        switch message.role {
        case .user:
            return [.text(role: .user, text: message.text)]
        case .assistant:
            return [.text(role: .assistant, text: message.text)]
        case .activity:
            guard let activity = message.activity,
                  let output = activity.output else {
                return []
            }
            let callID = "history-\(activity.id.uuidString.lowercased())"
            return [
                .toolCall(
                    id: callID,
                    name: activity.toolName,
                    arguments: activity.arguments
                ),
                .toolResult(
                    id: callID,
                    content: ComputerUseModelToolOutput.normalizePersisted(
                        toolName: activity.toolName,
                        output: output,
                        maximumTokens: policy.maximumToolOutputTokens
                    )
                ),
            ]
        }
    }

    private func persistedScreenshotReference(
        for message: ComputerUseConversationMessage
    ) -> PersistedScreenshotReference? {
        guard message.role == .activity,
              let activity = message.activity,
              let output = activity.output else {
            return nil
        }
        return ComputerUseModelToolOutput.persistedScreenshotReference(
            toolName: activity.toolName,
            output: output
        )
    }

    private func groupProtocolMessages(
        _ messages: [ComputerUseModelMessage]
    ) -> [MessageGroup] {
        var groups: [MessageGroup] = []
        var index = 0
        while index < messages.count {
            let message = messages[index]
            if let call = message.singleToolCall,
               index + 1 < messages.count,
               messages[index + 1].toolCallID == call.id {
                var grouped = [message, messages[index + 1]]
                index += 2
                if index < messages.count, messages[index].isImage {
                    grouped.append(messages[index])
                    index += 1
                }
                groups.append(
                    MessageGroup(
                        messages: grouped,
                        isObservation: call.function.name == ComputerUseToolName.getAppState.rawValue
                    )
                )
                continue
            }
            groups.append(MessageGroup(messages: [message], isObservation: false))
            index += 1
        }
        return groups
    }
}

enum ComputerUseModelToolOutput {
    static func encode(
        _ result: ComputerUseToolResult,
        maximumTokens: Int
    ) throws -> String {
        let output: String
        switch result {
        case let .applications(applications):
            output = try encodeJSON(applications)
        case let .appState(state):
            output = try encodeJSON(ModelVisibleAppState(app: state.app, text: state.text))
        case .actionCompleted:
            output = "null"
        }
        return ComputerUseTokenTruncator.truncateMiddle(output, maximumTokens: maximumTokens)
    }

    static func normalizePersisted(
        toolName: String,
        output: String,
        maximumTokens: Int
    ) -> String {
        var normalized = output
        if toolName == ComputerUseToolName.getAppState.rawValue,
           let data = output.data(using: .utf8),
           var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object.removeValue(forKey: "screenshot")
            if let cleanData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ) {
                normalized = String(decoding: cleanData, as: UTF8.self)
            }
        }
        return ComputerUseTokenTruncator.truncateMiddle(
            normalized,
            maximumTokens: maximumTokens
        )
    }

    static func persistedScreenshotReference(
        toolName: String,
        output: String
    ) -> PersistedScreenshotReference? {
        guard toolName == ComputerUseToolName.getAppState.rawValue,
              let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = object["app"] as? String,
              let screenshot = object["screenshot"] as? String,
              let url = URL(string: screenshot),
              url.isFileURL else {
            return nil
        }
        return PersistedScreenshotReference(app: app, url: url)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private struct ModelVisibleAppState: Encodable {
        let app: String
        let text: String
    }
}

struct PersistedScreenshotReference: Equatable, Sendable {
    let app: String
    let url: URL
}

enum ComputerUseTokenTruncator {
    private static let approximateBytesPerToken = 4

    static func approximateTokenCount(_ text: String) -> Int {
        let bytes = text.utf8.count
        return (bytes + approximateBytesPerToken - 1) / approximateBytesPerToken
    }

    static func truncateMiddle(_ text: String, maximumTokens: Int) -> String {
        guard !text.isEmpty else { return "" }
        let maximumBytes = max(0, maximumTokens) * approximateBytesPerToken
        guard maximumBytes > 0, text.utf8.count > maximumBytes else {
            return maximumBytes == 0
                ? "…\(approximateTokenCount(text)) tokens truncated…"
                : text
        }

        let leftBudget = maximumBytes / 2
        let rightBudget = maximumBytes - leftBudget
        let prefixEnd = validUTF8Boundary(in: text, near: leftBudget, movingForward: false)
        let suffixTarget = text.utf8.count - rightBudget
        let suffixStart = validUTF8Boundary(in: text, near: suffixTarget, movingForward: true)
        let removedBytes = max(0, text.utf8.count - maximumBytes)
        let removedTokens = (removedBytes + approximateBytesPerToken - 1)
            / approximateBytesPerToken
        let prefix = utf8Slice(text, from: 0, to: prefixEnd)
        let suffix = utf8Slice(text, from: suffixStart, to: text.utf8.count)
        return "\(prefix)…\(removedTokens) tokens truncated…\(suffix)"
    }

    private static func validUTF8Boundary(
        in text: String,
        near offset: Int,
        movingForward: Bool
    ) -> Int {
        var candidate = min(max(0, offset), text.utf8.count)
        while candidate >= 0 && candidate <= text.utf8.count {
            let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: candidate)
            if String.Index(utf8Index, within: text) != nil { return candidate }
            candidate += movingForward ? 1 : -1
        }
        return movingForward ? text.utf8.count : 0
    }

    private static func utf8Slice(_ text: String, from: Int, to: Int) -> Substring {
        let lowerUTF8 = text.utf8.index(text.utf8.startIndex, offsetBy: from)
        let upperUTF8 = text.utf8.index(text.utf8.startIndex, offsetBy: to)
        let lower = String.Index(lowerUTF8, within: text) ?? text.startIndex
        let upper = String.Index(upperUTF8, within: text) ?? text.endIndex
        return text[lower..<upper]
    }
}

private struct MessageGroup {
    let messages: [ComputerUseModelMessage]
    let isObservation: Bool

    var tokenCount: Int {
        messages.reduce(0) { $0 + $1.approximateTokenCount }
    }
}

extension ComputerUseModelMessage {
    var textContent: String? {
        guard case let .text(text) = content else { return nil }
        return text
    }

    fileprivate var isImage: Bool {
        guard case let .parts(parts) = content else { return false }
        return parts.contains { part in
            if case .image = part { return true }
            return false
        }
    }

    fileprivate var singleToolCall: ComputerUseModelWireToolCall? {
        guard toolCalls?.count == 1 else { return nil }
        return toolCalls?.first
    }

    fileprivate var approximateTokenCount: Int {
        var count = 4
        if let textContent {
            count += ComputerUseTokenTruncator.approximateTokenCount(textContent)
        }
        if let toolCalls {
            for call in toolCalls {
                count += ComputerUseTokenTruncator.approximateTokenCount(call.function.name)
                count += ComputerUseTokenTruncator.approximateTokenCount(call.function.arguments)
            }
        }
        if case let .parts(parts) = content {
            for part in parts {
                switch part {
                case let .text(text):
                    count += ComputerUseTokenTruncator.approximateTokenCount(text)
                case .image:
                    count += 1_024
                }
            }
        }
        return count
    }
}
