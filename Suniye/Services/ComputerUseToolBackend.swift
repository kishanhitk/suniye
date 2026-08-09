import Foundation

protocol ComputerUseActionSettling: Sendable {
    func waitForUIToSettle() async throws
}

actor ComputerUseToolBackend: ComputerUseToolServing {
    private let applications: ComputerUseApplicationCatalogProviding
    private let windows: ComputerUseWindowDiscovering
    private let observations: ComputerUseObserving
    private let actions: ComputerUseActionServing
    private let settler: ComputerUseActionSettling
    private var observationsByTarget: [String: ComputerUseObservation] = [:]

    init(
        applications: ComputerUseApplicationCatalogProviding = ComputerUseApplicationCatalog(),
        windows: ComputerUseWindowDiscovering = ComputerUseWindowDiscovery(),
        observations: ComputerUseObserving? = nil,
        actions: ComputerUseActionServing = ComputerUseActionService(),
        settler: ComputerUseActionSettling = SystemComputerUseActionSettler()
    ) {
        self.applications = applications
        self.windows = windows
        self.observations = observations ?? ComputerUseObservationService(
            windows: windows
        )
        self.actions = actions
        self.settler = settler
    }

    func listApps() async throws -> [ComputerUseApplication] {
        try Task.checkCancellation()
        return try await applications.listApps()
    }

    func getAppState(app: String, disableDiff: Bool) async throws -> ComputerUseAppState {
        try Task.checkCancellation()
        let application = try await applications.resolveOrLaunch(app)
        let key = targetKey(application)
        observationsByTarget.removeValue(forKey: key)
        let observation = try await observations.observe(
            application: application,
            requestedIdentifier: app,
            disableDiff: disableDiff
        )
        observationsByTarget[key] = observation
        return observation.state
    }

    func click(_ request: ComputerUseClickRequest) async throws {
        try await performAction(app: request.app) { context in
            try await actions.click(request, context: context)
        }
    }

    func performSecondaryAction(app: String, elementIndex: Int, action: String) async throws {
        try await performAction(app: app) { context in
            try await actions.performSecondaryAction(
                action,
                elementIndex: elementIndex,
                context: context
            )
        }
    }

    func setValue(app: String, elementIndex: Int, value: String) async throws {
        try await performAction(app: app) { context in
            try await actions.setValue(value, elementIndex: elementIndex, context: context)
        }
    }

    func selectText(
        app: String,
        elementIndex: Int,
        text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType
    ) async throws {
        try await performAction(app: app) { context in
            try await actions.selectText(
                text,
                elementIndex: elementIndex,
                prefix: prefix,
                suffix: suffix,
                selectionType: selectionType,
                context: context
            )
        }
    }

    func scroll(
        app: String,
        elementIndex: Int,
        direction: ComputerUseScrollDirection,
        pages: Double
    ) async throws {
        try await performAction(app: app) { context in
            try await actions.scroll(
                elementIndex: elementIndex,
                direction: direction,
                pages: pages,
                context: context
            )
        }
    }

    func drag(
        app: String,
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double
    ) async throws {
        try await performAction(app: app) { context in
            try await actions.drag(
                fromX: fromX,
                fromY: fromY,
                toX: toX,
                toY: toY,
                context: context
            )
        }
    }

    func pressKey(app: String, key: String) async throws {
        try await performAction(app: app) { context in
            try await actions.pressKey(key, context: context)
        }
    }

    func typeText(app: String, text: String) async throws {
        try await performAction(app: app) { context in
            try await actions.typeText(text, context: context)
        }
    }

    private func performAction(
        app: String,
        operation: (ComputerUseActionContext) async throws -> Void
    ) async throws {
        try await operation(context(for: app))
        try await finishAction()
    }

    private func context(for app: String) async throws -> ComputerUseActionContext {
        try Task.checkCancellation()
        let application = try await applications.resolveOrLaunch(app)
        let key = targetKey(application)
        guard let observation = observationsByTarget.removeValue(forKey: key) else {
            throw ComputerUseActionError.observationRequired(app)
        }
        guard application.processIdentifier == observation.target.application.processIdentifier,
              let pid = application.processIdentifier else {
            throw ComputerUseActionError.staleObservation(app)
        }
        let currentWindows = try await windows.orderedWindows(processIdentifier: pid)
        guard let window = currentWindows.first(where: { $0.id == observation.target.window.id })
        else {
            throw ComputerUseActionError.staleObservation(app)
        }
        return ComputerUseActionContext(
            target: ComputerUseObservedTarget(application: application, window: window),
            revision: observation.revision,
            screenshot: observation.screenshot
        )
    }

    private func finishAction() async throws {
        try Task.checkCancellation()
        try await settler.waitForUIToSettle()
        try Task.checkCancellation()
    }

    private func targetKey(_ application: ComputerUseApplicationRecord) -> String {
        application.bundleIdentifier ?? application.applicationURL.standardizedFileURL.path
    }
}

struct SystemComputerUseActionSettler: ComputerUseActionSettling {
    private let delay: Duration

    init(delay: Duration = .seconds(1)) {
        self.delay = delay
    }

    func waitForUIToSettle() async throws {
        try await Task.sleep(for: delay)
    }
}
