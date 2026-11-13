import AppKit
import ApplicationServices
import CoreAudio
import Darwin

/// The Core Audio process list: the call apps and browsers that hold the
/// microphone and play sound. It also listens for input devices that start
/// or stop running, so that the detector reads nothing while no input runs.
/// Nothing here opens a device.
@MainActor
final class CoreAudioMicrophoneUsers: MicrophoneUserReading {
    /// A browser that does not answer an Accessibility request in this time
    /// counts as showing no call.
    static let accessibilityTimeout: Float = 0.25

    var onInputActivityChanged: (() -> Void)?

    /// The call app or browser of each Core Audio process, nil for any other
    /// app. A process keeps its object ID while it runs, so a read asks only
    /// the call apps and browsers whether they run audio.
    private var appsByProcess: [AudioObjectID: MeetingCallApp?] = [:]
    private var watchedDevices: [AudioObjectID] = []
    private var listening = false
    /// One block for both properties: a new device list registers the device
    /// listeners again; a device that starts or stops running only tells the
    /// detector.
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, addresses in
        let deviceListChanged = addresses.pointee.mSelector == kAudioHardwarePropertyDevices
        MainActor.assumeIsolated {
            if deviceListChanged {
                self?.devicesChanged()
            } else {
                self?.onInputActivityChanged?()
            }
        }
    }

    var anyInputRunning: Bool {
        inputDevices().contains { uint32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 }
    }

    func startListening() {
        guard !listening else { return }
        listening = true
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        watchDevices()
    }

    func stopListening() {
        guard listening else { return }
        listening = false
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        unwatchDevices()
    }

    func read() -> [MicrophoneUser] {
        let processes = objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        let current = Set(processes)
        appsByProcess = appsByProcess.filter { current.contains($0.key) }
        var apps: [String: MeetingCallApp] = [:]
        var input: Set<String> = []
        var output: Set<String> = []
        for process in processes {
            guard let app = app(of: process) else { continue }
            apps[app.bundleID] = app
            if uint32(process, kAudioProcessPropertyIsRunningInput) == 1 {
                input.insert(app.bundleID)
            }
            if uint32(process, kAudioProcessPropertyIsRunningOutput) == 1 {
                output.insert(app.bundleID)
            }
        }
        return input.sorted().compactMap { id in
            apps[id].map { MicrophoneUser(app: $0, playsOutput: output.contains(id)) }
        }
    }

    func showsMeeting(_ browser: MeetingCallApp) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).contains { app in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            return Self.elements(of: element, kAXWindowsAttribute).contains { window in
                Self.string(of: window, kAXTitleAttribute).map(MeetingCallApps.titleShowsMeeting) ?? false
            }
        }
    }

    // MARK: - Listeners

    private func devicesChanged() {
        unwatchDevices()
        watchDevices()
        onInputActivityChanged?()
    }

    private func watchDevices() {
        watchedDevices = inputDevices()
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        for device in watchedDevices {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
    }

    private func unwatchDevices() {
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        for device in watchedDevices {
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
        }
        watchedDevices = []
    }

    private func inputDevices() -> [AudioObjectID] {
        CoreAudioDeviceCatalog.availableInputDevices().compactMap { CoreAudioDeviceCatalog.deviceID(forUID: $0.id) }
    }

    // MARK: - Reads

    private static func elements(of element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, accessibilityTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        AXUIElementSetMessagingTimeout(element, accessibilityTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func app(of process: AudioObjectID) -> MeetingCallApp? {
        if let known = appsByProcess[process] {
            return known
        }
        let identifier = bundleID(of: process) ?? int32(process, kAudioProcessPropertyPID).flatMap(processName)
        let app = identifier.flatMap(MeetingCallApps.app(forProcess:))
        appsByProcess.updateValue(app, forKey: process)
        return app
    }

    private func bundleID(of process: AudioObjectID) -> String? {
        var address = Self.address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    private func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = Self.address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func int32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        uint32(object, selector).map { Int32(bitPattern: $0) }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
