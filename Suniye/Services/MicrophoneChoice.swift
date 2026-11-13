import Foundation
import Observation

/// Which microphone Suniye records from, and why. The saved choice stays in
/// `GeneralSettings`; this type reads it and writes it through AppState's one
/// settings write path.
@MainActor
@Observable
final class MicrophoneChoice {
    /// The connected devices, plus the saved one as `.notConnected` while it is unplugged.
    var availableInputDevices: [AudioInputDevice] = []
    /// The route a dictation would record from now, or the route the running
    /// dictation records from.
    private(set) var audioRouteSnapshot: AudioRouteSnapshot? {
        didSet {
            if audioRouteSnapshot != nil {
                audioRouteErrorText = nil
            }
        }
    }
    /// Why no microphone can record, while `audioRouteSnapshot` is nil.
    private(set) var audioRouteErrorText: String?

    @ObservationIgnored private let audioCaptureService: AudioCaptureServiceProtocol
    @ObservationIgnored private let settings: () -> GeneralSettings
    @ObservationIgnored private let updateSettings: ((inout GeneralSettings) -> Void) -> Void
    @ObservationIgnored private let echoCancellationEnabled: () -> Bool
    @ObservationIgnored private let isDictating: () -> Bool

    init(
        audioCaptureService: AudioCaptureServiceProtocol,
        settings: @escaping () -> GeneralSettings,
        updateSettings: @escaping ((inout GeneralSettings) -> Void) -> Void,
        echoCancellationEnabled: @escaping () -> Bool,
        isDictating: @escaping () -> Bool
    ) {
        self.audioCaptureService = audioCaptureService
        self.settings = settings
        self.updateSettings = updateSettings
        self.echoCancellationEnabled = echoCancellationEnabled
        self.isDictating = isDictating
    }

    var selectedInputDeviceID: String? {
        get { settings().preferredInputDeviceID }
        set { select(newValue) }
    }

    var preferredInputDeviceName: String? {
        settings().preferredInputDeviceName
    }

    func refreshInputDevices() {
        applyInputDevices(audioCaptureService.availableInputDevices())
        refreshAudioRouteSnapshot()
    }

    func applyInputDevices(_ devices: [AudioInputDevice]) {
        if let selectedInputDeviceID,
           let name = Self.connectedName(of: selectedInputDeviceID, in: devices),
           preferredInputDeviceName != name {
            updateSettings { $0.preferredInputDeviceName = name }
        }
        var visibleDevices = devices
        if let selectedInputDeviceID, !devices.contains(where: { $0.id == selectedInputDeviceID }) {
            visibleDevices.append(
                AudioInputDevice(
                    id: selectedInputDeviceID,
                    name: preferredInputDeviceName ?? "Selected Microphone",
                    isDefault: false,
                    transport: .other,
                    availability: .notConnected
                )
            )
        }
        availableInputDevices = visibleDevices
    }

    /// While a dictation runs, the route stays the one it records from. Device
    /// changes apply to the next dictation, so the route refreshes when it ends.
    func refreshAudioRouteSnapshot() {
        guard !isDictating() else {
            return
        }
        do {
            audioRouteSnapshot = try audioCaptureService.routeSnapshot(
                preferredInputDeviceID: selectedInputDeviceID,
                echoCancellationEnabled: echoCancellationEnabled()
            )
        } catch {
            audioRouteSnapshot = nil
            audioRouteErrorText = error.localizedDescription
        }
    }

    /// The running dictation's route, from its capture start and its route changes.
    func adoptSessionRoute(_ route: AudioRouteSnapshot) {
        audioRouteSnapshot = route
    }

    func useRecommendedInputDevice() {
        guard let recommendedInputDevice else {
            return
        }
        select(recommendedInputDevice.id)
    }

    /// The microphone Suniye records from, which can be a stand-in for the saved one.
    var activeInputDeviceName: String {
        if let route = audioRouteSnapshot {
            return route.effectiveInputName
        }
        if let selectedInputDeviceID {
            return availableInputDevices.first(where: { $0.id == selectedInputDeviceID })?.name
                ?? preferredInputDeviceName
                ?? "Selected Microphone"
        }
        return availableInputDevices.first(where: \.isDefault)?.name ?? "System Default"
    }

    var effectiveInputDeviceStatusText: String {
        guard let route = audioRouteSnapshot else {
            return audioRouteErrorText ?? AudioCaptureServiceError.noInputDevice.localizedDescription
        }
        return inputStandInNote ?? "Using \(route.effectiveInputName) - \(route.inputTransport.title)"
    }

    /// Names the microphone Suniye uses in place of the chosen one, and why.
    var inputStandInNote: String? {
        guard let route = audioRouteSnapshot, let standIn = route.standIn else {
            return nil
        }
        let skipped: String
        switch standIn {
        case .preferredMissing:
            skipped = "\(preferredInputDeviceName ?? "The selected microphone") isn't connected"
        case let .offWithLidClosed(name):
            skipped = "\(name) is off while the lid is closed"
        case let .bluetoothDefault(name):
            skipped = "\(name) is Bluetooth"
        }
        return "\(skipped), so \(AppIdentity.current.displayName) uses \(route.effectiveInputName)."
    }

    /// The info tip of the input picker: only while it says "System Default" and
    /// so hides the device, and no stand-in note or warning row already says it.
    var inputDeviceInfoText: String? {
        guard selectedInputDeviceID == nil, audioRouteSnapshot != nil, inputStandInNote == nil else {
            return nil
        }
        return effectiveInputDeviceStatusText
    }

    var audioRouteWarningText: String? {
        guard let route = audioRouteSnapshot else {
            return nil
        }
        if route.inputTransport.isBluetooth {
            return "Bluetooth microphones put headphones into call-quality audio while dictating."
        }
        if route.requestedEchoCancellation, !route.effectiveEchoCancellation {
            return "Echo cancellation is unavailable for the current audio route."
        }
        return nil
    }

    var recommendedInputDevice: AudioInputDevice? {
        let effectiveID = audioRouteSnapshot?.effectiveInputDeviceID
        return availableInputDevices
            .filter { $0.isAvailable && $0.transport.isRecommendedPhysicalInput && $0.id != effectiveID }
            .sorted {
                if $0.isDefault != $1.isDefault {
                    return $0.isDefault
                }
                if $0.transport != $1.transport {
                    return $0.transport == .builtIn
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .first
    }

    /// Saving a choice also saves the device's name, so that settings can name
    /// it while it is unplugged. A nil choice means "System Default".
    private func select(_ id: String?) {
        let name = id.flatMap { Self.connectedName(of: $0, in: availableInputDevices) }
        updateSettings { settings in
            settings.preferredInputDeviceID = id
            if let name {
                settings.preferredInputDeviceName = name
            } else if id == nil {
                settings.preferredInputDeviceName = nil
            }
        }
    }

    /// The listed name of a device the system reports. The saved device's
    /// stand-in entry (`.notConnected`) has no real name to store.
    private static func connectedName(of id: String, in devices: [AudioInputDevice]) -> String? {
        devices.first { $0.id == id && $0.availability != .notConnected }?.name
    }
}
