import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftUI

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
    var wordsTranscribed = 0
    var sessionCount = 0
    var totalDictationSeconds: TimeInterval = 0
    var recentResults: [String] = []

    var showOnboarding = false

    var hasMicPermission = false
    var hasAccessibilityPermission = false

    var isModelInstalled: Bool {
        modelManager.isModelReady()
    }

    var onStateChange: (() -> Void)?

    private let modelManager = ModelManager()
    private let transcriptionService = TranscriptionService()
    private let audioCaptureService = AudioCaptureService()
    private let textInsertionService = TextInsertionService()
    private let hotkeyService = HotkeyService()
    private let floatingIndicatorController = FloatingIndicatorController()

    private var recordingStart: Date?
    private var pendingProcessingIndicatorTask: Task<Void, Never>?

    init() {
        AppLogger.shared.log(.info, "app state init")
        wireHotkey()
        Task {
            await bootstrap()
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
            let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

            if !trimmed.isEmpty {
                if !hasAccessibilityPermission {
                    await refreshPermissions(promptAccessibility: true)
                }
                guard hasAccessibilityPermission else {
                    throw NSError(domain: "VibeStoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accessibility permission not granted"])
                }
                try textInsertionService.insertText(trimmed)
                sessionCount += 1
                wordsTranscribed += wordCount
                recentResults.insert(trimmed, at: 0)
                if recentResults.count > 12 {
                    recentResults.removeLast(recentResults.count - 12)
                }
                AppLogger.shared.log(.info, "transcription complete words=\(wordCount)")
            }
            if trimmed.isEmpty {
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
