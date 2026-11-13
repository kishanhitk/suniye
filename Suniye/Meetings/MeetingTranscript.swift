import Foundation
import NaturalLanguage

/// Rules that turn the stored segments of a meeting into the transcript that
/// people read.
///
/// When the call plays on speakers, the microphone also hears it, so the "You"
/// track repeats words of the "Them" track. The echo filter drops a "You"
/// segment when most of its words are in "Them" segments near it in time.
enum MeetingTranscript {
    /// How far apart in time an echo and its source can be (1.5 s).
    static let echoWindowSamples = 3 * MeetingAudioFormat.sampleRate / 2
    /// The share of a segment's words that must be in the nearby call text.
    static let echoShare = 0.6

    static func ordered(_ segments: [MeetingSegment]) -> [MeetingSegment] {
        segments.sorted { ($0.audioStart, $0.track.rawValue) < ($1.audioStart, $1.track.rawValue) }
    }

    /// Every segment in time order, without the echo segments.
    /// The transcript that a reader sees: no echo of the call, and no line
    /// after the end of the call that the meeting followed.
    static func final(_ segments: [MeetingSegment], of record: MeetingRecord) -> [MeetingSegment] {
        let kept = record.transcriptEnd.map { end in segments.filter { $0.audioStart < end } } ?? segments
        return final(kept, callPlayedOnSpeakers: record.callPlayedOnSpeakers)
    }

    static func final(_ segments: [MeetingSegment], callPlayedOnSpeakers: Bool) -> [MeetingSegment] {
        guard callPlayedOnSpeakers else { return ordered(segments) }
        let call = segments.filter { $0.track == .them }
        return ordered(segments.filter { $0.track == .them || !isEcho($0, call: call) })
    }

    /// What the live view shows. A "You" segment waits until the call track
    /// is decoded past its end plus the echo window. Then the echo check sees
    /// every call segment that can be its source, and no earlier call line
    /// arrives after it. `callDecodedThrough` is nil when no call track
    /// records.
    static func live(
        _ segments: [MeetingSegment],
        callDecodedThrough: Int?,
        callPlayedOnSpeakers: Bool
    ) -> [MeetingSegment] {
        guard let callDecodedThrough else { return final(segments, callPlayedOnSpeakers: callPlayedOnSpeakers) }
        let ready = segments.filter { $0.track == .them || $0.audioEnd + echoWindowSamples <= callDecodedThrough }
        return final(ready, callPlayedOnSpeakers: callPlayedOnSpeakers)
    }

    /// One line per turn: segments of one track in a row join into one turn.
    /// `timeline` adds the wall-clock time of each turn; `speakerLabels`
    /// adds "You" or "Them", and is false when the meeting had no call track.
    static func turns(
        _ segments: [MeetingSegment],
        timeline: MeetingTimeline?,
        speakerLabels: Bool
    ) -> [String] {
        var turns: [(track: MeetingTrack, start: Int, text: String)] = []
        for segment in ordered(segments) {
            if let last = turns.last, last.track == segment.track {
                turns[turns.count - 1].text += " " + segment.text
            } else {
                turns.append((segment.track, segment.audioStart, segment.text))
            }
        }
        return turns.map { turn in
            var line = ""
            if let timeline {
                line += "[\(clock(timeline.wallSeconds(forSample: turn.start)))] "
            }
            if speakerLabels {
                line += turn.track == .you ? "You: " : "Them: "
            }
            return line + turn.text
        }
    }

    /// "04:05" under an hour, "1:04:05" from an hour on.
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }

    static func isEcho(_ segment: MeetingSegment, call: [MeetingSegment]) -> Bool {
        let spoken = words(in: segment.text)
        guard !spoken.isEmpty else { return false }
        var heard = Set<String>()
        for source in call
            where source.audioEnd + echoWindowSamples >= segment.audioStart
            && source.audioStart <= segment.audioEnd + echoWindowSamples {
            heard.formUnion(words(in: source.text))
        }
        let repeated = spoken.filter(heard.contains).count
        return Double(repeated) >= echoShare * Double(spoken.count)
    }

    static func words(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex ..< text.endIndex).map { text[$0].lowercased() }
    }
}
