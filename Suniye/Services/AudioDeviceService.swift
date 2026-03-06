import AVFoundation
import CoreAudio
import Foundation

protocol AudioDeviceServiceProtocol {
    func availableInputDevices() -> [AudioInputDevice]
    func defaultInputDeviceUID() -> String?
    func resolveSelectedInputDeviceUID(_ preferredUID: String?) -> String?
    func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID?
}

final class AudioDeviceService: AudioDeviceServiceProtocol {
    func availableInputDevices() -> [AudioInputDevice] {
        let defaultUID = defaultInputDeviceUID()
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
            .map { device in
                AudioInputDevice(
                    uid: device.uniqueID,
                    name: device.localizedName,
                    isDefault: device.uniqueID == defaultUID
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault && !rhs.isDefault
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return devices
    }

    func defaultInputDeviceUID() -> String? {
        AVCaptureDevice.default(for: .audio)?.uniqueID
    }

    func resolveSelectedInputDeviceUID(_ preferredUID: String?) -> String? {
        let devices = availableInputDevices()
        if let preferredUID,
           devices.contains(where: { $0.uid == preferredUID }) {
            return preferredUID
        }
        return devices.first?.uid
    }

    func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        let deviceIDs = allAudioDeviceIDs()
        for deviceID in deviceIDs {
            guard let currentUID = deviceUID(for: deviceID) else {
                continue
            }
            if currentUID == uid {
                return deviceID
            }
        }
        return nil
    }

    private func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            return []
        }

        return deviceIDs
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var cfUID: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &cfUID) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr else {
            return nil
        }

        return cfUID as String?
    }
}
