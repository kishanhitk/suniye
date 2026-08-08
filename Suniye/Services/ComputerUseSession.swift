actor ComputerUseSession {
    private let backend: ComputerUseToolServing

    init(backend: ComputerUseToolServing) {
        self.backend = backend
    }

    func execute(_ call: ComputerUseToolCall) async throws -> ComputerUseToolResult {
        try Task.checkCancellation()

        let result: ComputerUseToolResult
        switch call {
        case .listApps:
            result = .applications(try await backend.listApps())
        case let .getAppState(app, disableDiff):
            let state = try await backend.getAppState(app: app, disableDiff: disableDiff)
            result = .appState(state)
        case let .click(request):
            try await backend.click(request)
            result = .actionCompleted
        case let .performSecondaryAction(app, elementIndex, action):
            try await backend.performSecondaryAction(
                app: app,
                elementIndex: elementIndex,
                action: action
            )
            result = .actionCompleted
        case let .setValue(app, elementIndex, value):
            try await backend.setValue(app: app, elementIndex: elementIndex, value: value)
            result = .actionCompleted
        case let .selectText(app, elementIndex, text, prefix, suffix, selectionType):
            try await backend.selectText(
                app: app,
                elementIndex: elementIndex,
                text: text,
                prefix: prefix,
                suffix: suffix,
                selectionType: selectionType
            )
            result = .actionCompleted
        case let .scroll(app, elementIndex, direction, pages):
            try await backend.scroll(
                app: app,
                elementIndex: elementIndex,
                direction: direction,
                pages: pages
            )
            result = .actionCompleted
        case let .drag(app, fromX, fromY, toX, toY):
            try await backend.drag(
                app: app,
                fromX: fromX,
                fromY: fromY,
                toX: toX,
                toY: toY
            )
            result = .actionCompleted
        case let .pressKey(app, key):
            try await backend.pressKey(app: app, key: key)
            result = .actionCompleted
        case let .typeText(app, text):
            try await backend.typeText(app: app, text: text)
            result = .actionCompleted
        }

        return result
    }
}
