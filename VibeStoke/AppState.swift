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

    var downloadProgress: Double = 0

    var sessionCount = 0
    var wordsTranscribed = 0
    var totalDictationSeconds: TimeInterval = 0
    var historyEntries: [HistoryEntry] = []
    var historyActionMessage: String?

    var recentResults: [String] {
        Array(historyEntries.prefix(12).map(\.text))
    }

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

    var hotkeyShortcut: HotkeyShortcut = .defaultHoldToTalk {
        didSet {
            guard !isHydratingPreferences else {
                return
            }
            if hotkeyShortcut.isEmpty {
                hotkeyShortcut = .defaultHoldToTalk
                hotkeyValidationError = "Shortcut cannot be empty."
                return
            }
            hotkeyValidationError = nil
            persistAppPreferences()
            hotkeyService.updateShortcut(hotkeyShortcut)
            onStateChange?()
        }
    }
    var hotkeyValidationError: String?

    var availableInputDevices: [AudioInputDevice] = []
    var selectedInputDeviceUID: String? {
        didSet {
            guard !isHydratingPreferences else {
                return
            }
            persistAppPreferences()
            onStateChange?()
        }
    }
    var inputDeviceStatusMessage: String?

    var launchAtLoginEnabled = false {
        didSet {
            guard !isHydratingPreferences else {
                return
            }
            persistAppPreferences()
            onStateChange?()
        }
    }
    var launchAtLoginError: String?

    var modelDiagnostics: ModelDiagnostics?
    var modelDiagnosticsError: String?

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

    var llmVocabulary: [String] {
        LLMDefaults.parseKeywords(from: llmKeywordsRaw)
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
    private let historyStore: HistoryStoreProtocol
    private let statsStore: StatsStoreProtocol
    private let appPreferencesStore: AppPreferencesStoreProtocol
    private let audioDeviceService: AudioDeviceServiceProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol

    private let historyLimit = 500

    private var recordingStart: Date?
    private var pendingProcessingIndicatorTask: Task<Void, Never>?
    private var isHydratingLLMSettings = false
    private var isHydratingPreferences = false
    private let llmE2EMode: LLME2EMode

    init(
        modelManager: ModelManager = ModelManager(),
        transcriptionService: TranscriptionService = TranscriptionService(),
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        textInsertionService: TextInsertionService = TextInsertionService(),
        hotkeyService: HotkeyService = HotkeyService(),
        llmPostProcessor: LLMPostProcessor = OpenRouterPostProcessor(),
        llmSettingsStore: LLMSettingsStoreProtocol = LLMSettingsStore(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        historyStore: HistoryStoreProtocol = HistoryStore(),
        statsStore: StatsStoreProtocol = StatsStore(),
        appPreferencesStore: AppPreferencesStoreProtocol = AppPreferencesStore(),
        audioDeviceService: AudioDeviceServiceProtocol = AudioDeviceService(),
        launchAtLoginService: LaunchAtLoginServiceProtocol = LaunchAtLoginService(),
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
        self.historyStore = historyStore
        self.statsStore = statsStore
        self.appPreferencesStore = appPreferencesStore
        self.audioDeviceService = audioDeviceService
        self.launchAtLoginService = launchAtLoginService
        self.llmE2EMode = llmE2EMode ?? AppState.detectLLME2EMode(arguments: CommandLine.arguments)

        AppLogger.shared.log(.info, "app state init")
        loadLLMSettings()
        loadHistoryAndStats()
        loadAppPreferences()
        refreshAudioDevices(emitFallbackNotice: false)
        refreshLaunchAtLoginState()
        refreshLLMKeyStatus()
        refreshModelDiagnostics()

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
        refreshModelDiagnostics()
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
                refreshModelDiagnostics()
                AppLogger.shared.log(.info, "model download complete")
            } catch {
                phase = .error
                lastError = error.localizedDescription
                statusText = "Download failed"
                refreshModelDiagnostics()
                AppLogger.shared.log(.error, "model download failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshModelDiagnostics() {
        do {
            modelDiagnostics = try modelManager.modelDiagnostics()
            modelDiagnosticsError = nil
        } catch {
            modelDiagnostics = nil
            modelDiagnosticsError = error.localizedDescription
        }
        onStateChange?()
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

    func refreshAudioDevices(emitFallbackNotice: Bool = true) {
        let devices = audioDeviceService.availableInputDevices()
        availableInputDevices = devices

        let resolvedUID = audioDeviceService.resolveSelectedInputDeviceUID(selectedInputDeviceUID)
        if let selectedInputDeviceUID,
           resolvedUID != selectedInputDeviceUID,
           emitFallbackNotice {
            inputDeviceStatusMessage = "Selected input device is unavailable. Falling back to default input."
        }
        selectedInputDeviceUID = resolvedUID

        if resolvedUID == nil && devices.isEmpty {
            inputDeviceStatusMessage = "No audio input devices found."
        }

        onStateChange?()
    }

    func selectInputDevice(uid: String?) {
        let resolved = audioDeviceService.resolveSelectedInputDeviceUID(uid)
        selectedInputDeviceUID = resolved
        if let uid, resolved != uid {
            inputDeviceStatusMessage = "Selected input device is unavailable."
        } else {
            inputDeviceStatusMessage = nil
        }
        onStateChange?()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLoginService.isEnabled()
            launchAtLoginError = nil
            persistAppPreferences()
        } catch {
            launchAtLoginEnabled = launchAtLoginService.isEnabled()
            launchAtLoginError = error.localizedDescription + " Install VibeStoke in /Applications and retry."
        }
        onStateChange?()
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = launchAtLoginService.isEnabled()
        onStateChange?()
    }

    func filteredHistoryEntries(searchText: String) -> [HistoryEntry] {
        let normalized = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return historyEntries
        }

        return historyEntries.filter { entry in
            entry.text.localizedCaseInsensitiveContains(normalized)
        }
    }

    func copyHistoryEntryText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        historyActionMessage = "Copied"
        onStateChange?()
    }

    func deleteHistoryEntry(id: UUID) {
        guard let index = historyEntries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = historyEntries.remove(at: index)
        var stats = currentStatsSnapshot()
        stats.applyRemovedEntry(removed)
        applyStats(stats)
        persistHistoryAndStats()
        historyActionMessage = "Deleted"
        onStateChange?()
    }

    func clearHistory() {
        historyEntries.removeAll(keepingCapacity: false)
        applyStats(.zero)
        persistHistoryAndStats()
        historyActionMessage = "History cleared"
        onStateChange?()
    }

    func addVocabularyTerm(_ rawTerm: String) {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return
        }

        var terms = llmVocabulary
        if !terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
            terms.append(term)
            llmKeywordsRaw = terms.joined(separator: "\n")
        }
    }

    func removeVocabularyTerm(_ term: String) {
        let terms = llmVocabulary.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        llmKeywordsRaw = terms.joined(separator: "\n")
    }

    func updateHotkeyShortcut(_ shortcut: HotkeyShortcut) {
        if shortcut.isEmpty {
            hotkeyValidationError = "Shortcut cannot be empty."
            return
        }
        hotkeyShortcut = shortcut
        hotkeyValidationError = nil
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

        hotkeyService.startMonitoring(shortcut: hotkeyShortcut)
        AppLogger.shared.log(.info, "hotkey monitoring started shortcut=\(hotkeyShortcut.displayText)")
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
            showIndicator(.error(message: "Enable Accessibility for hotkey"), autoHideAfter: 2.2)
            return
        }
        startRecording()
    }

    private func startRecording() {
        guard phase == .ready else {
            return
        }

        do {
            try audioCaptureService.startCapture(selectedInputDeviceUID: selectedInputDeviceUID)
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
                addHistoryEntry(
                    text: finalText,
                    durationSeconds: duration,
                    wordCount: wordCount,
                    submitted: shouldSubmit
                )
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

    func addHistoryEntry(text: String, durationSeconds: TimeInterval, wordCount: Int, submitted: Bool) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        let entry = HistoryEntry(
            durationSeconds: durationSeconds,
            wordCount: wordCount,
            text: normalized,
            submitted: submitted
        )

        historyEntries.insert(entry, at: 0)

        var stats = currentStatsSnapshot()
        stats.applyAddedEntry(entry)

        if historyEntries.count > historyLimit {
            let overflow = historyEntries.suffix(from: historyLimit)
            for removed in overflow {
                stats.applyRemovedEntry(removed)
            }
            historyEntries = Array(historyEntries.prefix(historyLimit))
        }

        applyStats(stats)
        persistHistoryAndStats()
        onStateChange?()
    }

    private func loadHistoryAndStats() {
        historyEntries = historyStore.load()
        let stats = statsStore.load()
        applyStats(stats)
    }

    private func persistHistoryAndStats() {
        historyStore.save(historyEntries)
        statsStore.save(currentStatsSnapshot())
    }

    private func applyStats(_ snapshot: StatsSnapshot) {
        sessionCount = snapshot.sessionCount
        wordsTranscribed = snapshot.wordsTranscribed
        totalDictationSeconds = snapshot.totalDictationSeconds
    }

    private func currentStatsSnapshot() -> StatsSnapshot {
        StatsSnapshot(
            sessionCount: sessionCount,
            wordsTranscribed: wordsTranscribed,
            totalDictationSeconds: totalDictationSeconds
        )
    }

    private func loadAppPreferences() {
        isHydratingPreferences = true
        let preferences = appPreferencesStore.load()
        hotkeyShortcut = preferences.hotkeyShortcut.isEmpty ? .defaultHoldToTalk : preferences.hotkeyShortcut
        selectedInputDeviceUID = preferences.selectedInputDeviceUID
        launchAtLoginEnabled = preferences.launchAtLoginEnabled
        isHydratingPreferences = false
    }

    private func persistAppPreferences() {
        guard !isHydratingPreferences else {
            return
        }

        appPreferencesStore.save(
            AppPreferences(
                hotkeyShortcut: hotkeyShortcut,
                selectedInputDeviceUID: selectedInputDeviceUID,
                launchAtLoginEnabled: launchAtLoginEnabled
            )
        )
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
