import AppKit
import Foundation

extension MeetingEnvironment {
    /// The tap API exists from macOS 14.2, but 14.2 and 14.3 ask for a
    /// different permission, so call audio needs 14.4.
    static var canRecordCallAudio: Bool {
        if #available(macOS 14.4, *) {
            return true
        }
        return false
    }

    /// The Mac itself: the meeting microphone, the call audio tap, the
    /// first-recording notice, the disk and the output device.
    @MainActor
    static func live() -> MeetingEnvironment {
        MeetingEnvironment(
            makeSources: { includeCallAudio, preferred in
                var sources: [MeetingTrack: MeetingAudioSource] = [.you: MeetingMicCapture(preferredInputDeviceID: preferred)]
                if includeCallAudio, #available(macOS 14.4, *) {
                    sources[.them] = SystemAudioTap()
                }
                return sources
            },
            confirmNotice: { MeetingNoticeAlert.confirm(includesCallAudio: canRecordCallAudio) },
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

/// The first-recording notice: an app-modal alert, so it shows in front of
/// the call whichever surface started the recording.
@MainActor
enum MeetingNoticeAlert {
    static let sentence = "I’m recording this call to take notes. The recording stays on my computer."

    static func confirm(includesCallAudio: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Before you record"
        alert.informativeText = includesCallAudio
            ? "Suniye records your microphone and the sound of the call. Let everyone in the call know.\n\nAudio and transcripts stay on this Mac."
            : "Suniye records your microphone. Let everyone in the call know.\n\nAudio and transcripts stay on this Mac.\n\nRecording a call needs macOS 14.4 or later."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let copier = SentenceCopier(sentence: sentence)
        alert.accessoryView = copier.view
        NSApp.activate(ignoringOtherApps: true)
        return withExtendedLifetime(copier) {
            alert.runModal() == .alertFirstButtonReturn
        }
    }

    @MainActor
    private final class SentenceCopier: NSObject {
        let view: NSView
        private let sentence: String
        private let button: NSButton

        init(sentence: String) {
            self.sentence = sentence
            let label = NSTextField(wrappingLabelWithString: "“\(sentence)”")
            label.isSelectable = true
            label.preferredMaxLayoutWidth = 260
            button = NSButton(title: "Copy", target: nil, action: nil)
            let stack = NSStackView(views: [label, button])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.frame = NSRect(x: 0, y: 0, width: 260, height: stack.fittingSize.height)
            view = stack
            super.init()
            button.target = self
            button.action = #selector(copySentence)
        }

        @objc private func copySentence() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sentence, forType: .string)
            button.title = "Copied"
        }
    }
}
