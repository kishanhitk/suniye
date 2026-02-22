import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftUI

enum LLME2EMode {
    case none
    case forceSuccess
    case forceFailure

    var logValue: String {
        switch self {
        case .none:
            return "none"
        case .forceSuccess:
            return "success"
        case .forceFailure:
            return "fallback"
        }
    }
}

@MainActor
@Observable
final class AppState {
    enum Phase: String {
        case needsModel
        case downloadingModel
        case loading
        case ready
        case recording
        case transcribing
        case error
    }

    enum UpdateStatus: String {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case error
    }

    var phase: Phase = .loading {
        didSet {
            if oldValue != phase {
                onStateChange?()
                AppLogger.shared.log(.info, "phase changed: \(oldValue.rawValue) -> \(phase.rawValue)")
            }
        }
    }
    var statusText = "Initializing..." {
        didSet {
            if oldValue != statusText {
                onStateChange?()
            }
        }
    }
    var lastError: String?

    var updateStatus: UpdateStatus = .idle {
        didSet {
            if oldValue != updateStatus {
                onStateChange?()
                AppLogger.shared.log(.info, "update status changed: \(oldValue.rawValue) -> \(updateStatus.rawValue)")
            }
        }
    }
    var availableUpdateVersion: String? {
        didSet {
            if oldValue != availableUpdateVersion {
                onStateChange?()
            }
        }
    }
    var updateStatusText = "No update check yet." {
        didSet {
            if oldValue != updateStatusText {
                onStateChange?()
            }
        }
    }
    var updateDownloadProgress: Double = 0 {
        didSet {
            if oldValue != updateDownloadProgress {
                onStateChange?()
            }
        }
    }

    var downloadProgress: Double = 0
    var wordsTranscribed = 0
    var sessionCount = 0
    var totalDictationSeconds: TimeInterval = 0
    var recentResults: [String] = []

    var showOnboarding = false

    var hasMicPermission = false
    var hasAccessibilityPermission = false

    var llmEnabled = false {
        didSet { persistLLMSettings() }
    }
    var llmSelectedModelPreset: LLMModelPreset = .gemini25Flash {
        didSet { persistLLMSettings() }
    }
    var llmCustomModelId = "" {
        didSet { persistLLMSettings() }
    }
    var llmBaseSystemPrompt = LLMDefaults.defaultBaseSystemPrompt {
        didSet { persistLLMSettings() }
    }
    var llmSystemPrompt = "" {
        didSet { persistLLMSettings() }
    }
    var llmKeywordsRaw = "" {
        didSet { persistLLMSettings() }
    }

    var hasOpenRouterAPIKey = false {
        didSet {
            if oldValue != hasOpenRouterAPIKey {
                onStateChange?()
            }
        }
    }
    var llmKeyOperationError: String?

    var isModelInstalled: Bool {
        modelManager.isModelReady()
    }

    var llmKeyStatusText: String {
        hasOpenRouterAPIKey ? "API key: saved" : "API key: missing"
    }

    var llmStatusHint: String? {
        if llmEnabled && !hasOpenRouterAPIKey {
            return "LLM enabled but API key missing"
        }
        return nil
    }

    var llmSelectedModelIdPreview: String {
        currentLLMSettings().effectiveModelId
    }

    var onStateChange: (() -> Void)?

    private let modelManager: ModelManager
    private let transcriptionService: TranscriptionService
    private let audioCaptureService: AudioCaptureService
    private let textInsertionService: TextInsertionService
    private let hotkeyService: HotkeyService
    private let floatingIndicatorController = FloatingIndicatorController()
    private let llmPostProcessor: LLMPostProcessor
    private let llmSettingsStore: LLMSettingsStoreProtocol
    private let keychainService: KeychainServiceProtocol
    private let updateService: UpdateServiceProtocol
    private let currentAppVersionProvider: () -> AppVersion?

    private var recordingStart: Date?
    private var pendingProcessingIndicatorTask: Task<Void, Never>?
    private var isHydratingLLMSettings = false
    private let llmE2EMode: LLME2EMode
    private var availableUpdateRelease: UpdateRelease?

    init(
        modelManager: ModelManager = ModelManager(),
        transcriptionService: TranscriptionService = TranscriptionService(),
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        textInsertionService: TextInsertionService = TextInsertionService(),
        hotkeyService: HotkeyService = HotkeyService(),
        llmPostProcessor: LLMPostProcessor = OpenRouterPostProcessor(),
        llmSettingsStore: LLMSettingsStoreProtocol = LLMSettingsStore(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        updateService: UpdateServiceProtocol = GitHubUpdateService(),
        currentAppVersionProvider: @escaping () -> AppVersion? = { AppVersion.fromBundle() },
        startServices: Bool = true,
        llmE2EMode: LLME2EMode? = nil
    ) {
        self.modelManager = modelManager
        self.transcriptionService = transcriptionService
        self.audioCaptureService = audioCaptureService
        self.textInsertionService = textInsertionService
        self.hotkeyService = hotkeyService
        self.llmPostProcessor = llmPostProcessor
        self.llmSettingsStore = llmSettingsStore
        self.keychainService = keychainService
        self.updateService = updateService
        self.currentAppVersionProvider = currentAppVersionProvider
        self.llmE2EMode = llmE2EMode ?? AppState.detectLLME2EMode(arguments: CommandLine.arguments)

        AppLogger.shared.log(.info, "app state init")
        loadLLMSettings()
        refreshLLMKeyStatus()

        if startServices {
            wireHotkey()
            Task {
                await bootstrap()
            }
        }
    }

    func bootstrap() async {
        AppLogger.shared.log(.info, "bootstrap start")
        statusText = "Checking permissions..."
        await refreshPermissions()

        statusText = "Checking model..."
        if modelManager.isModelReady() {
            phase = .ready
            statusText = "Ready"
            await loadRecognizerIfPossible()
            floatingIndicatorController.hide()
        } else {
            phase = .needsModel
            statusText = "Model required"
            showOnboarding = true
            floatingIndicatorController.hide()
        }
        AppLogger.shared.log(.info, "bootstrap done")
    }

    func refreshPermissions(requestMicrophone: Bool = false, promptAccessibility: Bool = false) async {
        if requestMicrophone {
            hasMicPermission = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            hasMicPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }

        if promptAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        } else {
            hasAccessibilityPermission = AXIsProcessTrusted()
        }

        AppLogger.shared.log(.info, "permissions: mic=\(hasMicPermission) ax=\(hasAccessibilityPermission)")
        onStateChange?()
    }

    func requestAccessibilityPermission() {
        Task {
            await refreshPermissions(promptAccessibility: true)
        }
    }

    func refreshLLMKeyStatus() {
        hasOpenRouterAPIKey = keychainService.hasOpenRouterKey()
    }

    func saveOpenRouterAPIKey(_ key: String) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            llmKeyOperationError = "API key cannot be empty"
            onStateChange?()
            return
        }

        do {
            try keychainService.setOpenRouterKey(normalized)
            llmKeyOperationError = nil
            refreshLLMKeyStatus()
            AppLogger.shared.log(.info, "openrouter api key saved")
        } catch {
            llmKeyOperationError = "Failed to save API key"
            AppLogger.shared.log(.error, "openrouter api key save failed")
            onStateChange?()
        }
    }

    func clearOpenRouterAPIKey() {
        do {
            try keychainService.deleteOpenRouterKey()
            llmKeyOperationError = nil
            refreshLLMKeyStatus()
            AppLogger.shared.log(.info, "openrouter api key cleared")
        } catch {
            llmKeyOperationError = "Failed to clear API key"
            AppLogger.shared.log(.error, "openrouter api key clear failed")
            onStateChange?()
        }
    }

    func startModelDownload() {
        guard phase != .recording && phase != .transcribing else {
            return
        }

        phase = .downloadingModel
        statusText = "Downloading model..."
        lastError = nil
        downloadProgress = 0

        Task {
            do {
                AppLogger.shared.log(.info, "model download started")
                try await modelManager.downloadAndExtractModel { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }

                phase = .loading
                statusText = "Validating model..."

                guard modelManager.isModelReady() else {
                    throw AppStateError.modelValidationFailed
                }

                await loadRecognizerIfPossible()
                phase = .ready
                statusText = "Ready"
                showOnboarding = false
                AppLogger.shared.log(.info, "model download complete")
            } catch {
                phase = .error
                lastError = error.localizedDescription
                statusText = "Download failed"
                AppLogger.shared.log(.error, "model download failed: \(error.localizedDescription)")
            }
        }
    }

    func openModelFolder() {
        do {
            let folder = try modelManager.modelDirectoryURL().deletingLastPathComponent()
            NSWorkspace.shared.open(folder)
            AppLogger.shared.log(.info, "open model folder: \(folder.path)")
        } catch {
            AppLogger.shared.log(.error, "open model folder failed: \(error.localizedDescription)")
        }
    }

    func openMainWindow() {
        MainWindowController.shared.show(appState: self)
    }

    func startRecordingFromUI() {
        Task { @MainActor in
            await beginRecordingFlow()
        }
    }

    func stopRecordingFromUI() {
        guard phase == .recording else {
            return
        }
        Task {
            await stopRecordingAndTranscribe()
        }
    }

    func checkForUpdatesOnLaunch() async {
        await checkForUpdates(background: true)
    }

    func checkForUpdates(background: Bool) async {
        guard updateStatus != .checking, updateStatus != .downloading else {
            return
        }

        updateStatus = .checking
        if !background {
            updateStatusText = "Checking for updates..."
        }

        guard let currentVersion = currentAppVersionProvider() else {
            AppLogger.shared.log(.error, "update check failed: local app version missing")
            if background {
                updateStatus = .idle
            } else {
                updateStatus = .error
                updateStatusText = "Unable to read local app version."
            }
            return
        }

        do {
            let result = try await updateService.checkForUpdate(currentVersion: currentVersion)
            switch result {
            case .upToDate:
                availableUpdateRelease = nil
                availableUpdateVersion = nil
                if background {
                    updateStatus = .idle
                } else {
                    updateStatus = .upToDate
                    updateStatusText = "You're up to date."
                }
                AppLogger.shared.log(.info, "update check complete: up-to-date")
            case let .updateAvailable(release):
                availableUpdateRelease = release
                availableUpdateVersion = release.versionTag
                updateStatus = .available
                updateStatusText = "Update available: \(release.versionTag)"
                AppLogger.shared.log(.info, "update available: \(release.versionTag)")
            }
        } catch {
            AppLogger.shared.log(.warning, "update check failed: \(error.localizedDescription)")
            if background {
                updateStatus = .idle
            } else {
                updateStatus = .error
                updateStatusText = error.localizedDescription
            }
        }
    }

    func downloadAndOpenUpdate() async {
        guard updateStatus != .downloading else {
            return
        }
        guard let release = availableUpdateRelease else {
            updateStatus = .error
            updateStatusText = "No update is currently available."
            return
        }

        updateStatus = .downloading
        updateStatusText = "Downloading update..."
        updateDownloadProgress = 0

        do {
            let archiveURL = try await updateService.downloadAndVerify(release: release)
            updateDownloadProgress = 1
            updateStatus = .available
            updateStatusText = "Update downloaded. Installer opened."
            NSWorkspace.shared.open(archiveURL)
            AppLogger.shared.log(.info, "update download complete and opened: \(archiveURL.path)")
        } catch {
            updateStatus = .error
            updateStatusText = error.localizedDescription
            updateDownloadProgress = 0
            AppLogger.shared.log(.error, "update download failed: \(error.localizedDescription)")
        }
    }

    func openReleaseNotes() {
        guard let release = availableUpdateRelease else {
            return
        }
        NSWorkspace.shared.open(release.htmlURL)
    }

    func postProcessTextIfEnabled(_ rawText: String) async -> String {
        let input = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return rawText
        }

        switch llmE2EMode {
        case .forceSuccess:
            AppLogger.shared.log(.info, "llm e2e forced success")
            return "\(input)."
        case .forceFailure:
            AppLogger.shared.log(.warning, "llm e2e forced fallback")
            return rawText
        case .none:
            break
        }

        guard llmEnabled else {
            return rawText
        }

        guard hasOpenRouterAPIKey else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=missing_key")
            return rawText
        }

        guard let apiKey = try? keychainService.getOpenRouterKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=key_read_failed")
            refreshLLMKeyStatus()
            return rawText
        }

        let config = makeLLMConfig(apiKey: apiKey)
        let startTime = Date()
        statusText = "Polishing..."

        do {
            let polished = try await llmPostProcessor.polish(text: input, config: config)
            let normalized = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                AppLogger.shared.log(.warning, "llm fallback raw reason=empty_output model=\(config.modelId)")
                return rawText
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "llm polish success model=\(config.modelId) latency_ms=\(latencyMs)")
            return normalized
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            if let llmError = error as? LLMPostProcessorError {
                AppLogger.shared.log(.warning, "llm fallback raw reason=\(llmError.logValue) model=\(config.modelId) latency_ms=\(latencyMs)")
            } else {
                AppLogger.shared.log(.warning, "llm fallback raw reason=unknown model=\(config.modelId) latency_ms=\(latencyMs)")
            }
            return rawText
        }
    }

    func runIndicatorE2ESmoke() {
        Task { @MainActor in
            AppLogger.shared.log(.info, "e2e indicator smoke start")
            showIndicator(.listening)
            try? await Task.sleep(nanoseconds: 220_000_000)
            showIndicator(.stopped)
            try? await Task.sleep(nanoseconds: 220_000_000)
            showIndicator(.processing)
            try? await Task.sleep(nanoseconds: 220_000_000)
            showIndicator(.done(words: 4), autoHideAfter: 0.35)
            try? await Task.sleep(nanoseconds: 900_000_000)
            AppLogger.shared.log(.info, "e2e indicator smoke done")
            NSApp.terminate(nil)
        }
    }

    func runLLME2ESmoke() {
        Task { @MainActor in
            AppLogger.shared.log(.info, "e2e llm smoke start mode=\(llmE2EMode.logValue)")
            llmEnabled = true
            let input = "this is a llm smoke test"
            let output = await postProcessTextIfEnabled(input)
            let changed = output != input
            AppLogger.shared.log(.info, "e2e llm smoke result mode=\(llmE2EMode.logValue) changed=\(changed)")
            NSApp.terminate(nil)
        }
    }

    func runSubmitCommandE2ESmoke() {
        Task { @MainActor in
            AppLogger.shared.log(.info, "e2e submit smoke start")
            let cases: [(input: String, expectedText: String, expectedSubmit: Bool)] = [
                ("hello world send", "hello world", true),
                ("hello world, enter.", "hello world", true),
                ("send", "", true),
                ("please send me notes", "please send me notes", false)
            ]

            var passed = true
            for testCase in cases {
                let parsed = AppState.parseSubmitCommand(from: testCase.input)
                if parsed.text != testCase.expectedText || parsed.shouldSubmit != testCase.expectedSubmit {
                    passed = false
                    AppLogger.shared.log(.error, "e2e submit smoke case failed")
                }
            }

            AppLogger.shared.log(.info, "e2e submit smoke done passed=\(passed)")
            NSApp.terminate(nil)
        }
    }

    private func wireHotkey() {
        hotkeyService.onHotkeyDown = { [weak self] in
            AppLogger.shared.log(.debug, "hotkey callback: down")
            Task { @MainActor in
                await self?.beginRecordingFlow()
            }
        }

        hotkeyService.onHotkeyUp = { [weak self] in
            AppLogger.shared.log(.debug, "hotkey callback: up")
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        hotkeyService.startMonitoring()
        AppLogger.shared.log(.info, "hotkey monitoring started")
    }

    private func loadRecognizerIfPossible() async {
        do {
            let config = try modelManager.makeRecognizerConfig()
            try await transcriptionService.loadModel(config: config)
        } catch {
            phase = .error
            lastError = "Model load failed: \(error.localizedDescription)"
            statusText = "Load failed"
            AppLogger.shared.log(.error, "model load failed: \(error.localizedDescription)")
        }
    }

    private func beginRecordingFlow() async {
        guard phase == .ready else {
            AppLogger.shared.log(.debug, "start recording ignored in phase=\(phase.rawValue)")
            showIndicator(.error(message: startBlockedMessage(for: phase)), autoHideAfter: 1.2)
            return
        }
        if !hasMicPermission {
            await refreshPermissions(requestMicrophone: true)
        }
        guard hasMicPermission else {
            phase = .error
            lastError = "Microphone permission not granted"
            statusText = "Permission required"
            AppLogger.shared.log(.warning, "microphone permission denied")
            showIndicator(.error(message: "Microphone permission required"), autoHideAfter: 1.8)
            return
        }

        if !hasAccessibilityPermission {
            await refreshPermissions(promptAccessibility: true)
        }
        guard hasAccessibilityPermission else {
            phase = .error
            lastError = "Accessibility permission not granted"
            statusText = "Accessibility required"
            AppLogger.shared.log(.warning, "accessibility permission denied before recording")
            showIndicator(.error(message: "Enable Accessibility for Fn hotkey"), autoHideAfter: 2.2)
            return
        }
        startRecording()
    }

    private func startRecording() {
        guard phase == .ready else {
            return
        }

        do {
            try audioCaptureService.startCapture()
            phase = .recording
            statusText = "Recording"
            recordingStart = Date()
            pendingProcessingIndicatorTask?.cancel()
            pendingProcessingIndicatorTask = nil
            showIndicator(.listening)
            AppLogger.shared.log(.info, "recording started")
        } catch {
            phase = .error
            lastError = "Audio start failed: \(error.localizedDescription)"
            statusText = "Audio error"
            AppLogger.shared.log(.error, "audio start failed: \(error.localizedDescription)")
            showIndicator(.error(message: "Failed to start audio capture"), autoHideAfter: 1.8)
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard phase == .recording else {
            return
        }

        showIndicator(.stopped)
        phase = .transcribing
        statusText = "Transcribing..."
        pendingProcessingIndicatorTask?.cancel()
        pendingProcessingIndicatorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, self.phase == .transcribing else { return }
            self.showIndicator(.processing)
        }

        let captured = audioCaptureService.stopCapture()
        let samples = captured.samples
        let sampleRate = captured.sampleRate
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        totalDictationSeconds += duration
        AppLogger.shared.log(.info, "dictation stop samples=\(samples.count) sr=\(sampleRate) duration=\(String(format: "%.2f", duration))")

        do {
            let text = try await transcriptionService.transcribe(samples: samples, sampleRate: sampleRate)
            let rawText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let rawParse = AppState.parseSubmitCommand(from: rawText)
            var shouldSubmit = rawParse.shouldSubmit
            var finalText = rawParse.text

            if !finalText.isEmpty {
                finalText = await postProcessTextIfEnabled(finalText)
                let polishedParse = AppState.parseSubmitCommand(from: finalText)
                finalText = polishedParse.text
                shouldSubmit = shouldSubmit || polishedParse.shouldSubmit
            }

            let wordCount = finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

            if !finalText.isEmpty || shouldSubmit {
                if !hasAccessibilityPermission {
                    await refreshPermissions(promptAccessibility: true)
                }
                guard hasAccessibilityPermission else {
                    throw NSError(domain: "VibeStoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accessibility permission not granted"])
                }
            }

            if !finalText.isEmpty {
                try textInsertionService.insertText(finalText)
                sessionCount += 1
                wordsTranscribed += wordCount
                recentResults.insert(finalText, at: 0)
                if recentResults.count > 12 {
                    recentResults.removeLast(recentResults.count - 12)
                }
                AppLogger.shared.log(.info, "transcription complete words=\(wordCount)")
            }

            if shouldSubmit {
                if !finalText.isEmpty {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
                try textInsertionService.submitActiveInput()
                AppLogger.shared.log(.info, "submit command executed")
            }

            if finalText.isEmpty && !shouldSubmit {
                AppLogger.shared.log(.warning, "transcription returned empty text samples=\(samples.count) sr=\(sampleRate)")
            }
            pendingProcessingIndicatorTask?.cancel()
            pendingProcessingIndicatorTask = nil
            phase = .ready
            statusText = "Ready"
            showIndicator(.done(words: wordCount), autoHideAfter: 1.2)
        } catch {
            pendingProcessingIndicatorTask?.cancel()
            pendingProcessingIndicatorTask = nil
            phase = .error
            lastError = "Transcription failed: \(error.localizedDescription)"
            statusText = "Transcription error"
            AppLogger.shared.log(.error, "transcription failed: \(error.localizedDescription)")
            showIndicator(.error(message: "Transcription failed"), autoHideAfter: 1.8)
        }
    }

    private func loadLLMSettings() {
        isHydratingLLMSettings = true
        let settings = llmSettingsStore.load()
        llmEnabled = settings.isEnabled
        llmSelectedModelPreset = settings.selectedModelPreset
        llmCustomModelId = settings.customModelId
        llmBaseSystemPrompt = settings.baseSystemPrompt
        llmSystemPrompt = settings.systemPrompt
        llmKeywordsRaw = settings.keywordsRaw
        isHydratingLLMSettings = false
    }

    private func persistLLMSettings() {
        guard !isHydratingLLMSettings else {
            return
        }
        llmSettingsStore.save(currentLLMSettings())
        onStateChange?()
    }

    private func currentLLMSettings() -> LLMSettings {
        LLMSettings(
            isEnabled: llmEnabled,
            selectedModelPreset: llmSelectedModelPreset,
            customModelId: llmCustomModelId,
            baseSystemPrompt: llmBaseSystemPrompt,
            systemPrompt: llmSystemPrompt,
            keywordsRaw: llmKeywordsRaw,
            timeoutSeconds: 3,
            maxTokens: 128
        )
    }

    private func makeLLMConfig(apiKey: String) -> LLMConfig {
        let settings = currentLLMSettings()
        return LLMConfig(
            modelId: settings.effectiveModelId,
            systemPrompt: settings.composedSystemPrompt,
            keywords: settings.keywords,
            timeoutSeconds: 3,
            maxTokens: settings.maxTokens,
            apiKey: apiKey
        )
    }

    private func showIndicator(_ state: FloatingIndicatorState, autoHideAfter: TimeInterval? = nil) {
        floatingIndicatorController.show(state, autoHideAfter: autoHideAfter)
    }

    private func startBlockedMessage(for phase: Phase) -> String {
        switch phase {
        case .needsModel:
            return "Download model first"
        case .downloadingModel:
            return "Model download in progress"
        case .loading:
            return "Still loading model"
        case .ready:
            return "Ready"
        case .recording:
            return "Already listening"
        case .transcribing:
            return "Still processing previous clip"
        case .error:
            return "Resolve current error first"
        }
    }

    nonisolated static func parseSubmitCommand(from text: String) -> (text: String, shouldSubmit: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("", false)
        }

        let pattern = #"(?i)(?:^|\s)(send|enter)\b[\s\.\!\?,;:\)\]\"']*$"#
        guard let commandRange = trimmed.range(of: pattern, options: .regularExpression) else {
            return (trimmed, false)
        }

        var cleaned = String(trimmed[..<commandRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: #"[,\s]+$"#, with: "", options: .regularExpression)

        return (cleaned, true)
    }

    private static func detectLLME2EMode(arguments: [String]) -> LLME2EMode {
        if arguments.contains("--e2e-llm-success") {
            return .forceSuccess
        }
        if arguments.contains("--e2e-llm-fallback") {
            return .forceFailure
        }
        return .none
    }
}

private extension LLMPostProcessorError {
    var logValue: String {
        switch self {
        case .invalidConfiguration:
            return "invalid_config"
        case .timeout:
            return "timeout"
        case .unauthorized:
            return "unauthorized"
        case .provider:
            return "provider_error"
        case .malformedResponse:
            return "malformed_response"
        case .emptyOutput:
            return "empty_output"
        case .network:
            return "network"
        }
    }
}

enum AppStateError: LocalizedError {
    case modelValidationFailed

    var errorDescription: String? {
        switch self {
        case .modelValidationFailed:
            return "Model files are missing after extraction."
        }
    }
}
