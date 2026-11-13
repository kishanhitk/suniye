import SuniyeAnalytics

extension MeetingStartSource {
    var analyticsSource: MeetingSource {
        switch self {
        case .manual:
            return .manual
        case .offer:
            return .offer
        case .automatic:
            return .automatic
        }
    }
}

extension MeetingStopCause {
    var analyticsReason: MeetingStopReason {
        switch self {
        case .user:
            return .user
        case .callEnded:
            return .callEnded
        case .sleep:
            return .sleep
        case .timeLimit:
            return .timeLimit
        case .noSpeech:
            return .noSpeech
        case .diskFull:
            return .diskFull
        case .writeFailed:
            return .writeFailed
        case .quit:
            return .quit
        }
    }
}

extension MeetingTracks {
    init(_ tracks: [MeetingTrack]) {
        switch (tracks.contains(.you), tracks.contains(.them)) {
        case (true, true):
            self = .youThem
        case (true, false):
            self = .you
        case (false, true):
            self = .them
        case (false, false):
            self = .noTrack
        }
    }
}

extension MeetingSummaryProvider {
    var analyticsEngine: MeetingSummaryEngine {
        switch self {
        case .appleIntelligence:
            return .appleIntelligence
        case .localModel:
            return .localModel
        }
    }
}

extension MeetingCallCard {
    var analyticsKind: MeetingCallCardKind {
        switch self {
        case .offer:
            return .offer
        case .startedAutomatically:
            return .started
        case .callEnded:
            return .callEnded
        }
    }
}
