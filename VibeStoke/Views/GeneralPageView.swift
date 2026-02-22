import SwiftUI

struct GeneralPageView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("General")
                    .font(AppTypography.ui(size: 32, weight: .bold))

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About")
                            .font(AppTypography.ui(size: 16, weight: .semibold))

                        Text("VibeStoke \(appVersion)")
                            .font(AppTypography.ui(size: 13, weight: .medium))
                        Text("Local-first dictation powered by sherpa-onnx.")
                            .font(AppTypography.ui(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Input Device")
                            .font(AppTypography.ui(size: 16, weight: .semibold))

                        Picker("Input Device", selection: Binding<String?>(
                            get: { appState.selectedInputDeviceUID },
                            set: { appState.selectInputDevice(uid: $0) }
                        )) {
                            ForEach(appState.availableInputDevices) { device in
                                Text(device.isDefault ? "\(device.name) (Default)" : device.name)
                                    .tag(Optional(device.uid))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 420)

                        HStack(spacing: 10) {
                            Button("Refresh Devices") {
                                appState.refreshAudioDevices()
                            }
                            .buttonStyle(.bordered)
                        }

                        if let inputDeviceStatusMessage = appState.inputDeviceStatusMessage {
                            Text(inputDeviceStatusMessage)
                                .font(AppTypography.ui(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Launch at login", isOn: Binding(
                            get: { appState.launchAtLoginEnabled },
                            set: { appState.setLaunchAtLoginEnabled($0) }
                        ))

                        if let launchAtLoginError = appState.launchAtLoginError {
                            Text(launchAtLoginError)
                                .font(AppTypography.ui(size: 12))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Startup")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(appState.hasMicPermission ? "Microphone granted" : "Microphone missing", systemImage: "mic")
                        Label(appState.hasAccessibilityPermission ? "Accessibility granted" : "Accessibility missing", systemImage: "accessibility")

                        HStack(spacing: 10) {
                            Button("Request Microphone") {
                                Task {
                                    await appState.refreshPermissions(requestMicrophone: true)
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Request Accessibility") {
                                appState.requestAccessibilityPermission()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Permissions")
                }
            }
            .padding(22)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = (info?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let build = (info?[kCFBundleVersionKey as String] as? String) ?? "0"
        return "\(shortVersion) (\(build))"
    }
}
