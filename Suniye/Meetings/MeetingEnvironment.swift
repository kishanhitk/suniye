import Foundation

/// What the coordinator asks of the app.
@MainActor
protocol MeetingHost: AnyObject {
    /// The microphone that the user picked for dictation; nil for the default.
    var meetingInputDeviceID: String? { get }
    func requestMeetingMicrophoneAccess() async -> Bool
    /// A summary stopped using the model, so Magic Format can load its own
    /// prompt into the model's cache again.
    func meetingSummaryModelIsIdle()
}

/// What the coordinator needs from the Mac, so that tests can replace it.
struct MeetingEnvironment {
    var makeSources: @MainActor (_ includeCallAudio: Bool, _ preferredInputDeviceID: String?) -> [MeetingTrack: MeetingAudioSource]
    var confirmNotice: @MainActor () async -> Bool
    var freeDiskBytes: () -> Int64?
    var callPlaysOnSpeakers: () -> Bool
    var now: () -> Date
    var outputCheckInterval: Duration = .seconds(5)
}

/// Where the call plays, for the echo filter.
enum MeetingCallOutput {
    /// 'hdpn': the headphone jack of a built-in output device.
    static let headphonesDataSource: UInt32 = 0x6864_706E

    /// Bluetooth output, and the headphone jack, count as headphones. Built-in
    /// speakers, displays and USB devices count as speakers: a USB device can
    /// be a headset or a speaker, and a wrong "speakers" only lets the filter
    /// drop a line that repeats the call.
    static func playsOnSpeakers(transport: AudioDeviceTransport, dataSource: UInt32?) -> Bool {
        if transport.isBluetooth {
            return false
        }
        if transport == .builtIn {
            return dataSource != headphonesDataSource
        }
        return true
    }
}
