import Foundation

enum AudioDeviceTransport: String, Equatable, Codable, Sendable {
    case builtIn
    case usb
    case bluetooth
    case bluetoothLE
    case continuity
    case aggregate
    case virtual
    case other

    var title: String {
        switch self {
        case .builtIn: return "Built-in"
        case .usb: return "USB"
        case .bluetooth: return "Bluetooth"
        case .bluetoothLE: return "Bluetooth LE"
        case .continuity: return "Continuity"
        case .aggregate: return "Aggregate"
        case .virtual: return "Virtual"
        case .other: return "Other"
        }
    }

    var isBluetooth: Bool {
        self == .bluetooth || self == .bluetoothLE
    }

    /// A wired input Suniye may use in place of a skipped one. A virtual or
    /// aggregate input can record silence while its app is idle, and an iPhone's
    /// Continuity microphone prompts on the phone and can fail.
    var isRecommendedPhysicalInput: Bool {
        switch self {
        case .builtIn, .usb, .other:
            return true
        case .bluetooth, .bluetoothLE, .continuity, .aggregate, .virtual:
            return false
        }
    }
}

struct AudioInputDevice: Identifiable, Equatable, Codable, Sendable {
    enum Availability: String, Equatable, Codable, Sendable {
        case available
        /// The saved microphone, listed while it is disconnected.
        case notConnected
        /// A MacBook's built-in microphone: listed, but switched off in hardware.
        case offWithLidClosed
    }

    let id: String
    let name: String
    let isDefault: Bool
    let transport: AudioDeviceTransport
    let availability: Availability

    var isAvailable: Bool {
        availability == .available
    }

    init(
        id: String,
        name: String,
        isDefault: Bool,
        transport: AudioDeviceTransport = .other,
        availability: Availability = .available
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.transport = transport
        self.availability = availability
    }
}
