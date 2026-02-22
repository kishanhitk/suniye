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

    var phase: Phase = .loading
    var statusText = "Initializing..."
    var lastError: String?

    var downloadProgress: Double = 0
    var wordsTranscribed = 0
    var sessionCount = 0
    var totalDictationSeconds: TimeInterval = 0
    var recentResults: [String] = []

    var showOnboarding = false
    var showListeningOverlay = false

    var hasMicPermission = false
    var hasAccessibilityPermission = false

    private let modelManager = ModelManager()
    private let transcriptionService = TranscriptionService()
    private let audioCaptureService = AudioCaptureService()
    private let textInsertionService = TextInsertionService()
    private let hotkeyService = HotkeyService()

    private var recordingStart: Date?

    init() {
        wireHotkey()
        Task {
            await bootstrap()
        }
    }

    func bootstrap() async {
        statusText = "Checking permissions..."
        await refreshPermissions()

        statusText = "Checking model..."
        if modelManager.isModelReady() {
            phase = .ready
            statusText = "Ready"
            await loadRecognizerIfPossible()
        } else {
            phase = .needsModel
            statusText = "Model required"
            showOnboarding = true
        }
    }

    func refreshPermissions() async {
        hasMicPermission = await AVCaptureDevice.requestAccess(for: .audio)

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    func startModelDownload() {
        guard phase == .needsModel || phase == .downloadingModel || phase == .error else {
            return
        }

        phase = .downloadingModel
        statusText = "Downloading model..."
        lastError = nil
        downloadProgress = 0

        Task {
            do {
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
            } catch {
                phase = .error
                lastError = error.localizedDescription
                statusText = "Download failed"
            }
        }
    }

    func openMainWindow() {
        NSApp.sendAction(#selector(AppCommands.openMainWindow), to: nil, from: nil)
    }

    func startRecordingFromUI() {
        guard phase == .ready else {
            return
        }
        startRecording()
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
            Task { @MainActor in
                self?.startRecording()
            }
        }

        hotkeyService.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        hotkeyService.startMonitoring()
    }

    private func loadRecognizerIfPossible() async {
        do {
            let config = try modelManager.makeRecognizerConfig()
            try await transcriptionService.loadModel(config: config)
        } catch {
            phase = .error
            lastError = "Model load failed: \(error.localizedDescription)"
            statusText = "Load failed"
        }
    }

    private func startRecording() {
        guard phase == .ready else {
            return
        }
        guard hasMicPermission else {
            phase = .error
            lastError = "Microphone permission not granted"
            statusText = "Permission required"
            return
        }

        do {
            try audioCaptureService.startCapture()
            phase = .recording
            statusText = "Recording"
            showListeningOverlay = true
            recordingStart = Date()
        } catch {
            phase = .error
            lastError = "Audio start failed: \(error.localizedDescription)"
            statusText = "Audio error"
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard phase == .recording else {
            return
        }

        showListeningOverlay = false
        phase = .transcribing
        statusText = "Transcribing..."

        let samples = audioCaptureService.stopCapture()
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        totalDictationSeconds += duration

        do {
            let text = try await transcriptionService.transcribe(samples: samples)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try textInsertionService.insertText(text)
                sessionCount += 1
                wordsTranscribed += text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                recentResults.insert(text, at: 0)
                if recentResults.count > 12 {
                    recentResults.removeLast(recentResults.count - 12)
                }
            }
            phase = .ready
            statusText = "Ready"
        } catch {
            phase = .error
            lastError = "Transcription failed: \(error.localizedDescription)"
            statusText = "Transcription error"
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

@objc final class AppCommands: NSObject {
    @objc func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == "VibeStoke" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
