import SuniyeAnalytics

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
