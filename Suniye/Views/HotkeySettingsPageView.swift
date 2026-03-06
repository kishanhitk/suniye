import AppKit
import SwiftUI

struct HotkeySettingsPageView: View {
    @Bindable var appState: AppState
    @State private var isCapturing = false
    @State private var captureStatusText = ""
    @State private var localMonitor: Any?
    @State private var modifierOnlyCandidate: HotkeyShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hotkey")
                .font(AppTypography.ui(size: 32, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Current shortcut")
                    .font(AppTypography.ui(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(appState.hotkeyShortcut.displayText)
                    .font(AppTypography.mono(size: 18, weight: .semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button(isCapturing ? "Recording..." : "Record Shortcut") {
                    if isCapturing {
                        stopCapture(cancelled: true)
                    } else {
                        beginCapture()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Reset to Fn") {
                    appState.updateHotkeyShortcut(.defaultHoldToTalk)
                    captureStatusText = "Reset to Fn"
                }
                .buttonStyle(.bordered)
            }

            Text(isCapturing ? "Press desired combo. For modifier-only, press and release modifier keys." : captureStatusText)
                .font(AppTypography.ui(size: 12))
                .foregroundStyle(.secondary)

            if let hotkeyValidationError = appState.hotkeyValidationError {
                Text(hotkeyValidationError)
                    .font(AppTypography.ui(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }

            Text("Hold-to-talk mode is always enabled: record starts on key down and stops on key up.")
                .font(AppTypography.ui(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(22)
        .onDisappear {
            stopCapture(cancelled: true)
        }
    }

    private func beginCapture() {
        stopCapture(cancelled: true)
        isCapturing = true
        modifierOnlyCandidate = nil
        captureStatusText = "Waiting for shortcut..."

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            guard isCapturing else {
                return event
            }

            switch event.type {
            case .keyDown:
                if event.keyCode == 53 {
                    stopCapture(cancelled: true)
                    return nil
                }

                let modifiers = HotkeyShortcut.Modifiers.from(event.modifierFlags)
                let shortcut = HotkeyShortcut(
                    keyCode: HotkeyShortcut.isModifierKeyCode(event.keyCode) ? nil : event.keyCode,
                    modifiers: modifiers
                )

                if shortcut.isEmpty {
                    return nil
                }

                appState.updateHotkeyShortcut(shortcut)
                captureStatusText = "Saved: \(shortcut.displayText)"
                stopCapture(cancelled: false)
                return nil

            case .flagsChanged:
                let modifiers = HotkeyShortcut.Modifiers.from(event.modifierFlags)

                if modifiers.isEmpty {
                    if let modifierOnlyCandidate {
                        appState.updateHotkeyShortcut(modifierOnlyCandidate)
                        captureStatusText = "Saved: \(modifierOnlyCandidate.displayText)"
                        stopCapture(cancelled: false)
                    }
                    return nil
                }

                modifierOnlyCandidate = HotkeyShortcut(keyCode: nil, modifiers: modifiers)
                return nil

            default:
                return event
            }
        }
    }

    private func stopCapture(cancelled: Bool) {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if cancelled, isCapturing {
            captureStatusText = "Shortcut recording cancelled"
        }
        modifierOnlyCandidate = nil
        isCapturing = false
    }
}
