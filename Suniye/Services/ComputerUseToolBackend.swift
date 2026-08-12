import Foundation

actor ComputerUseToolBackend: ComputerUseToolServing {
    private let applications: ComputerUseApplicationCatalogProviding
    private let windows: ComputerUseWindowDiscovering
    private let observations: ComputerUseObserving
    private let actions: ComputerUseActionServing
    private let settler: ComputerUseActionSettling
    private let runtimeGuard: ComputerUseRuntimeGuarding
    private let windowReacquisitionTimeout: Duration
    private let windowReacquisitionPollingInterval: Duration
    private var observationsByTarget: [String: AuthorizedObservation] = [:]

    private struct AuthorizedObservation {
        let observation: ComputerUseObservation
        let runtimeAuthorization: ComputerUseRuntimeAuthorization
    }

    private struct PreparedAction {
        let context: ComputerUseActionContext
        let runtimeAuthorization: ComputerUseRuntimeAuthorization
    }

    init(
        applications: ComputerUseApplicationCatalogProviding = ComputerUseApplicationCatalog(),
        windows: ComputerUseWindowDiscovering = ComputerUseWindowDiscovery(),
        observations: ComputerUseObserving? = nil,
        actions: ComputerUseActionServing = ComputerUseActionService(
            cursor: SystemComputerUseCursorPresenter()
        ),
        settler: ComputerUseActionSettling = SystemComputerUseActionSettler(),
        runtimeGuard: ComputerUseRuntimeGuarding = ComputerUseRuntimeGuard(),
        windowReacquisitionTimeout: Duration = .seconds(5),
        windowReacquisitionPollingInterval: Duration = .milliseconds(50)
    ) {
        self.applications = applications
        self.windows = windows
        self.observations = observations ?? ComputerUseObservationService(
            windows: windows
        )
        self.actions = actions
        self.settler = settler
        self.runtimeGuard = runtimeGuard
        self.windowReacquisitionTimeout = windowReacquisitionTimeout
        self.windowReacquisitionPollingInterval = windowReacquisitionPollingInterval
    }

    func listApps() async throws -> [ComputerUseApplication] {
        try Task.checkCancellation()
        return try await applications.listApps()
    }

    func getAppState(app: String, disableDiff: Bool) async throws -> ComputerUseAppState {
        try Task.checkCancellation()
        let runtimeAuthorization = try await runtimeGuard.prepareForObservation()
        let application = try await applications.resolveOrLaunch(app)
        let key = targetKey(application)
        observationsByTarget.removeValue(forKey: key)
        let observation = try await observe(
            application: application,
            requestedIdentifier: app,
            disableDiff: disableDiff
        )
        observationsByTarget[key] = AuthorizedObservation(
            observation: observation,
            runtimeAuthorization: runtimeAuthorization
        )
        return observation.state
    }

    private func observe(
        application: ComputerUseApplicationRecord,
        requestedIdentifier: String,
        disableDiff: Bool
    ) async throws -> ComputerUseObservation {
        do {
            return try await observations.observe(
                application: application,
                requestedIdentifier: requestedIdentifier,
                disableDiff: disableDiff
            )
        } catch ComputerUseObservationError.noWindow where application.isRunning {
            if let processIdentifier = application.processIdentifier,
               try await windows.waitUntilHasPrimaryWindow(
                   processIdentifier: processIdentifier,
                   timeout: windowReacquisitionTimeout,
                   pollingInterval: windowReacquisitionPollingInterval
               ) != nil {
                return try await observations.observe(
                    application: application,
                    requestedIdentifier: requestedIdentifier,
                    disableDiff: disableDiff
                )
            }

            let reopenedApplication = try await applications.reopen(application)
            return try await observations.observe(
                application: reopenedApplication,
                requestedIdentifier: requestedIdentifier,
                disableDiff: disableDiff
            )
        }
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
        let preparedAction = try await prepareAction(for: app)
        try await operation(preparedAction.context)
        try await finishAction(
            target: preparedAction.context.target,
            authorization: preparedAction.runtimeAuthorization
        )
    }

    private func prepareAction(for app: String) async throws -> PreparedAction {
        try Task.checkCancellation()
        let application = try await applications.resolveOrLaunch(app)
        let key = targetKey(application)
        guard let authorizedObservation = observationsByTarget.removeValue(forKey: key) else {
            throw ComputerUseActionError.observationRequired(app)
        }
        try await runtimeGuard.validateAction(authorizedObservation.runtimeAuthorization)
        let observation = authorizedObservation.observation
        guard application.processIdentifier == observation.target.application.processIdentifier,
              let pid = application.processIdentifier else {
            throw ComputerUseActionError.staleObservation(app)
        }
        let currentWindows = try await windows.orderedWindows(processIdentifier: pid)
        guard let window = currentWindows.first(where: { $0.id == observation.target.window.id })
        else {
            throw ComputerUseActionError.staleObservation(app)
        }
        return PreparedAction(
            context: ComputerUseActionContext(
                target: ComputerUseObservedTarget(application: application, window: window),
                revision: observation.revision,
                screenshot: observation.screenshot
            ),
            runtimeAuthorization: authorizedObservation.runtimeAuthorization
        )
    }

    private func finishAction(
        target: ComputerUseObservedTarget,
        authorization: ComputerUseRuntimeAuthorization
    ) async throws {
        try Task.checkCancellation()
        try await settler.waitForUIToSettle(target: target)
        try Task.checkCancellation()
        try await runtimeGuard.validateAction(authorization)
    }

    private func targetKey(_ application: ComputerUseApplicationRecord) -> String {
        application.bundleIdentifier ?? application.applicationURL.standardizedFileURL.path
    }
}
