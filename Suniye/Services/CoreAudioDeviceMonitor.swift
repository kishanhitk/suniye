import AudioToolbox
import CoreAudio
import Foundation

enum AudioDeviceChangeReason: String, Equatable, Sendable {
    case devices
    case defaultInput
    case defaultOutput
    case serviceRestarted
    case selectedDeviceAlive
    case selectedDeviceFormat
    case selectedDeviceChanged
    case inputMuted
    case ioStoppedAbnormally
    case processorOverload
}

protocol AudioDeviceMonitorProtocol: AnyObject {
    var onChange: ((AudioDeviceChangeReason) -> Void)? { get set }
    func start()
    func stop()
    func watch(deviceID: AudioObjectID?)
}

final class CoreAudioDeviceMonitor: AudioDeviceMonitorProtocol {
    var onChange: ((AudioDeviceChangeReason) -> Void)?

    private struct Listener {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "dev.suniye.audio.devices", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Void>()
    private var systemListeners: [Listener] = []
    private var deviceListeners: [Listener] = []
    private var started = false

    init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    func start() {
        perform {
            guard !self.started else { return }
            self.started = true
            let system = AudioObjectID(kAudioObjectSystemObject)
            self.systemListeners = [
                self.makeListener(objectID: system, selector: kAudioHardwarePropertyDevices, reason: .devices),
                self.makeListener(objectID: system, selector: kAudioHardwarePropertyDefaultInputDevice, reason: .defaultInput),
                self.makeListener(objectID: system, selector: kAudioHardwarePropertyDefaultOutputDevice, reason: .defaultOutput),
                self.makeListener(objectID: system, selector: kAudioHardwarePropertyServiceRestarted, reason: .serviceRestarted),
                self.makeListener(objectID: system, selector: kAudioHardwarePropertyProcessInputMute, reason: .inputMuted),
            ].compactMap { $0 }
        }
    }

    func stop() {
        perform {
            self.remove(&self.deviceListeners)
            self.remove(&self.systemListeners)
            self.started = false
        }
    }

    func watch(deviceID: AudioObjectID?) {
        perform {
            self.remove(&self.deviceListeners)
            guard let deviceID else { return }
            self.deviceListeners = [
                self.makeListener(objectID: deviceID, selector: kAudioDevicePropertyDeviceIsAlive, reason: .selectedDeviceAlive),
                self.makeListener(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyNominalSampleRate,
                    scope: kAudioDevicePropertyScopeInput,
                    reason: .selectedDeviceFormat
                ),
                self.makeListener(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyStreamConfiguration,
                    scope: kAudioDevicePropertyScopeInput,
                    reason: .selectedDeviceFormat
                ),
                self.makeListener(objectID: deviceID, selector: kAudioDevicePropertyDeviceHasChanged, reason: .selectedDeviceChanged),
                self.makeListener(objectID: deviceID, selector: kAudioDevicePropertyIOStoppedAbnormally, reason: .ioStoppedAbnormally),
                self.makeListener(objectID: deviceID, selector: kAudioDeviceProcessorOverload, reason: .processorOverload),
            ].compactMap { $0 }
        }
    }

    private func makeListener(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        reason: AudioDeviceChangeReason
    ) -> Listener? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onChange?(reason)
        }
        guard AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block) == noErr else {
            return nil
        }
        return Listener(objectID: objectID, address: address, block: block)
    }

    private func remove(_ listeners: inout [Listener]) {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.objectID, &address, queue, listener.block)
        }
        listeners.removeAll()
    }

    private func perform(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }
}

struct CoreAudioRouteResolution {
    let inputDeviceID: AudioObjectID
    let route: AudioDeviceRoute
}

protocol AudioCaptureHardwareCatalogProtocol {
    func availableInputDevices() -> [AudioInputDevice]
    func resolveDeviceRoute(preferredInputDeviceID: String?) throws -> CoreAudioRouteResolution
    func deviceID(forUID uid: String) -> AudioObjectID?
    func processIsRunningInput() -> Bool?
    func processInputIsMuted() -> Bool?
}

struct CoreAudioCaptureHardwareCatalog: AudioCaptureHardwareCatalogProtocol {
    func availableInputDevices() -> [AudioInputDevice] {
        CoreAudioDeviceCatalog.availableInputDevices()
    }

    func resolveDeviceRoute(preferredInputDeviceID: String?) throws -> CoreAudioRouteResolution {
        try CoreAudioDeviceCatalog.resolveDeviceRoute(preferredInputDeviceID: preferredInputDeviceID)
    }

    func deviceID(forUID uid: String) -> AudioObjectID? {
        CoreAudioDeviceCatalog.deviceID(forUID: uid)
    }

    func processIsRunningInput() -> Bool? {
        CoreAudioDeviceCatalog.processIsRunningInput()
    }

    func processInputIsMuted() -> Bool? {
        CoreAudioDeviceCatalog.processInputIsMuted()
    }
}

enum CoreAudioDeviceCatalog {
    static func availableInputDevices() -> [AudioInputDevice] {
        let defaultID = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        return allDeviceIDs()
            .filter { inputChannelCount(for: $0) > 0 && isAlive($0) }
            .compactMap { deviceID in
                guard let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                      let name = stringProperty(deviceID, selector: kAudioObjectPropertyName) else {
                    return nil
                }
                return AudioInputDevice(
                    id: uid,
                    name: name,
                    isDefault: deviceID == defaultID,
                    transport: transport(for: deviceID),
                    isAvailable: true
                )
            }
            .sorted {
                if $0.isDefault != $1.isDefault {
                    return $0.isDefault
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func resolveDeviceRoute(preferredInputDeviceID: String?) throws -> CoreAudioRouteResolution {
        let resolvedInputID: AudioObjectID
        if let preferredInputDeviceID {
            guard let preferred = deviceID(forUID: preferredInputDeviceID), isAlive(preferred), inputChannelCount(for: preferred) > 0 else {
                throw AudioCaptureServiceError.preferredDeviceUnavailable
            }
            resolvedInputID = preferred
        } else if let defaultInput = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice),
                  isAlive(defaultInput),
                  inputChannelCount(for: defaultInput) > 0 {
            resolvedInputID = defaultInput
        } else {
            throw AudioCaptureServiceError.noInputDevice
        }

        guard let inputUID = stringProperty(resolvedInputID, selector: kAudioDevicePropertyDeviceUID),
              let inputName = stringProperty(resolvedInputID, selector: kAudioObjectPropertyName) else {
            throw AudioCaptureServiceError.noInputDevice
        }
        let outputID = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let inputTransport = transport(for: resolvedInputID)
        let outputTransport = outputID.map(transport(for:)) ?? .other
        let route = AudioDeviceRoute(
            preferredInputDeviceID: preferredInputDeviceID,
            effectiveInputDeviceID: inputUID,
            effectiveInputName: inputName,
            inputTransport: inputTransport,
            outputTransport: outputTransport,
            nominalInputSampleRate: max(8_000, Int(nominalSampleRate(for: resolvedInputID).rounded())),
            inputChannelCount: inputChannelCount(for: resolvedInputID)
        )
        return CoreAudioRouteResolution(inputDeviceID: resolvedInputID, route: route)
    }

    static func processIsRunningInput() -> Bool? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var pid = ProcessInfo.processInfo.processIdentifier
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &processObject) == noErr,
              processObject != kAudioObjectUnknown else {
            return nil
        }
        return uint32Property(processObject, selector: kAudioProcessPropertyIsRunningInput).map { $0 != 0 }
    }

    static func processInputIsMuted() -> Bool? {
        uint32Property(
            AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessInputMute
        ).map { $0 != 0 }
    }

    static func deviceID(forUID uid: String) -> AudioObjectID? {
        allDeviceIDs().first { stringProperty($0, selector: kAudioDevicePropertyDeviceUID) == uid }
    }

    static func allDeviceIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        var values = Array(repeating: AudioObjectID(), count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &values) == noErr else {
            return []
        }
        return values
    }

    static func inputChannelCount(for deviceID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return 0
        }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        let list = pointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, list) == noErr else {
            return 0
        }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func nominalSampleRate(for deviceID: AudioObjectID) -> Double {
        doubleProperty(
            deviceID,
            selector: kAudioDevicePropertyNominalSampleRate,
            scope: kAudioDevicePropertyScopeInput
        ) ?? 16_000
    }

    static func transport(for deviceID: AudioObjectID) -> AudioDeviceTransport {
        guard let raw = uint32Property(deviceID, selector: kAudioDevicePropertyTransportType) else {
            return .other
        }
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
            return .usb
        case kAudioDeviceTransportTypeBluetooth:
            return .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            return .bluetoothLE
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return .continuity
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            return aggregateContainsBluetooth(deviceID) ? .bluetooth : .aggregate
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .other
        }
    }

    private static func aggregateContainsBluetooth(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return false
        }
        var subdevices = Array(
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(dataSize) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &subdevices) == noErr else {
            return false
        }
        return subdevices.contains { subdevice in
            let subTransport = uint32Property(subdevice, selector: kAudioDevicePropertyTransportType)
            return subTransport == kAudioDeviceTransportTypeBluetooth || subTransport == kAudioDeviceTransportTypeBluetoothLE
        }
    }

    private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioObjectID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &value) == noErr,
              value != kAudioObjectUnknown else {
            return nil
        }
        return value
    }

    private static func isAlive(_ deviceID: AudioObjectID) -> Bool {
        uint32Property(deviceID, selector: kAudioDevicePropertyDeviceIsAlive).map { $0 != 0 } ?? true
    }

    private static func stringProperty(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedValue: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &unmanagedValue) == noErr,
              let value = unmanagedValue?.takeRetainedValue() else {
            return nil
        }
        return value as String
    }

    private static func uint32Property(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func doubleProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }
}
