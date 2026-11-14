import SwiftUI

/// The Transcript tab of a meeting: the player bar while the meeting's audio
/// is on the Mac, and the transcript.
struct MeetingTranscriptPane: View {
    let playback: MeetingPlayback
    let id: UUID
    let lines: [MeetingTranscriptLine]
    let timeline: MeetingTimeline
    let hasAudio: Bool
    /// False while a meeting records: the microphone would hear the audio.
    let canPlay: Bool
    let isEditable: Bool
    let edited: (_ texts: [UUID: String], _ ended: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasAudio {
                MeetingPlayerBar(playback: playback, id: id, timeline: timeline, canPlay: canPlay)
            }
            MeetingTranscriptView(lines: lines, isEditable: isEditable, edited: edited)
        }
    }
}

/// Play or pause, the position, and the time as the lines show it.
struct MeetingPlayerBar: View {
    let playback: MeetingPlayback
    let id: UUID
    let timeline: MeetingTimeline
    let canPlay: Bool
    /// A drag moves the audio when it ends; until then the bar shows this.
    @State private var dragged: TimeInterval?
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: playOrPause) {
                MeetingIcon(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .disabled(!canPlay || isFailed)
            .help(isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            if isFailed {
                Text("Couldn’t play the audio.")
                    .font(AppTypography.callout)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                Spacer(minLength: 0)
            } else {
                Slider(value: Binding(get: { dragged ?? position }, set: move), in: 0 ... max(duration, 1)) { editing in
                    isDragging = editing
                    if !editing, let dragged {
                        playback.seek(to: dragged)
                        self.dragged = nil
                    }
                }
                .controlSize(.small)
                .disabled(!isOpen)
                .accessibilityLabel("Position")
                .accessibilityValue("\(clock(dragged ?? position)) of \(clock(duration))")
                Text("\(clock(dragged ?? position)) / \(clock(duration))")
                    .font(AppTypography.callout)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .monospacedDigit()
            }
        }
        .frame(height: AppMetrics.iconButtonSize)
        .background(MeetingSpaceKey(action: playOrPause))
        .onAppear { playback.open(id) }
    }

    private var isOpen: Bool {
        playback.meetingID == id
    }

    private var isPlaying: Bool {
        isOpen && playback.isPlaying
    }

    private var isFailed: Bool {
        isOpen && playback.failed
    }

    private var position: TimeInterval {
        isOpen ? playback.position : 0
    }

    private var duration: TimeInterval {
        isOpen ? playback.duration : 0
    }

    /// The time on the wall clock, as the lines show it: the paused time
    /// counts.
    private func clock(_ audioSeconds: TimeInterval) -> String {
        MeetingTranscript.clock(timeline.wallSeconds(forAudioSeconds: audioSeconds))
    }

    /// A drag waits for its end; a key or VoiceOver moves the audio at once.
    private func move(_ time: TimeInterval) {
        if isDragging {
            dragged = time
        } else {
            playback.seek(to: time)
        }
    }

    private func playOrPause() {
        guard canPlay, !isFailed else { return }
        if isPlaying {
            playback.pause()
        } else {
            playback.open(id)
            playback.play()
        }
    }
}
