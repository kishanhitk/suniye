import AppKit
import Foundation

extension MeetingEnvironment {
    /// The tap API exists from macOS 14.2, but 14.2 and 14.3 ask for a
    /// different permission, so call audio needs 14.4.
    private static var canRecordCallAudio: Bool {
        if #available(macOS 14.4, *) {
            return true
        }
        return false
    }

    @MainActor
    static func live() -> MeetingEnvironment {
        MeetingEnvironment(
            canRecordCallAudio: canRecordCallAudio,
            makeSources: { preferred in
                var sources: [MeetingTrack: MeetingAudioSource] = [.you: MeetingMicCapture(preferredInputDeviceID: preferred)]
                if #available(macOS 14.4, *) {
                    sources[.them] = SystemAudioTap()
                }
                return sources
            },
            freeDiskBytes: {
                let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                return (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
            },
            callPlaysOnSpeakers: {
                guard let output = CoreAudioDeviceCatalog.defaultOutput() else { return true }
                return MeetingCallOutput.playsOnSpeakers(transport: output.transport, dataSource: output.dataSource)
            },
            makeMicrophoneUsers: { CoreAudioMicrophoneUsers() },
            now: Date.init
        )
    }
}
