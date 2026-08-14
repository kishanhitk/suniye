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
    private var observationsByTarget: [String: ComputerUseObservation] = [:]

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

    @discardableResult
    func execute(_ call: ComputerUseToolCall) async throws -> ComputerUseToolResult {
        try Task.checkCancellation()
        switch call {
        case .listApps:
            return .applications(try await applications.listApps())
        case let .getAppState(app, disableDiff):
            return .appState(try await getAppState(app: app, disableDiff: disableDiff))
        case let .click(request):
            try await performAction(app: request.app) { context in
                try await actions.click(request, context: context)
            }
        case let .performSecondaryAction(app, elementIndex, action):
            try await performAction(app: app) { context in
                try await actions.performSecondaryAction(
                    action,
                    elementIndex: elementIndex,
                    context: context
                )
            }
        case let .setValue(app, elementIndex, value):
            try await performAction(app: app) { context in
                try await actions.setValue(value, elementIndex: elementIndex, context: context)
            }
        case let .selectText(app, elementIndex, text, prefix, suffix, selectionType):
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
        case let .scroll(app, elementIndex, direction, pages):
            try await performAction(app: app) { context in
                try await actions.scroll(
                    elementIndex: elementIndex,
                    direction: direction,
                    pages: pages,
                    context: context
                )
            }
        case let .drag(app, fromX, fromY, toX, toY):
            try await performAction(app: app) { context in
                try await actions.drag(
                    fromX: fromX,
                    fromY: fromY,
                    toX: toX,
                    toY: toY,
                    context: context
                )
            }
        case let .pressKey(app, key):
            try await performAction(app: app) { context in
                try await actions.pressKey(key, context: context)
            }
        case let .typeText(app, text):
            try await performAction(app: app) { context in
                try await actions.typeText(text, context: context)
            }
        }
        return .actionCompleted
    }

    private func getAppState(app: String, disableDiff: Bool) async throws -> ComputerUseAppState {
        try await runtimeGuard.ensureScreenUnlocked()
        let application = try await applications.resolveOrLaunch(app)
        observationsByTarget.removeValue(forKey: application.identityKey)
        let observation = try await observe(
            application: application,
            requestedIdentifier: app,
            disableDiff: disableDiff
        )
        observationsByTarget[application.identityKey] = observation
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

    private func performAction(
        app: String,
        operation: (ComputerUseActionContext) async throws -> Void
    ) async throws {
        let context = try await prepareAction(for: app)
        try await operation(context)
        try Task.checkCancellation()
        try await settler.waitForUIToSettle(target: context.target)
        try Task.checkCancellation()
        try await runtimeGuard.ensureScreenUnlocked()
    }

    private func prepareAction(for app: String) async throws -> ComputerUseActionContext {
        // Resolve-only: an action must never relaunch an app that quit after
        // observation; that surfaces as staleObservation instead.
        let application = try await applications.resolve(app)
        // Observe-before-act: each observation is consumed by exactly one action.
        guard let observation = observationsByTarget.removeValue(forKey: application.identityKey)
        else {
            throw ComputerUseActionError.observationRequired(app)
        }
        try await runtimeGuard.ensureScreenUnlocked()
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
}
