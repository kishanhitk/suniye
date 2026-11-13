import Foundation

/// The apps whose microphone use means a call.
enum MeetingCallApps {
    static let callApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.apple.FaceTime": "FaceTime",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.cisco.webexmeetingsapp": "Webex",
        "Cisco-Systems.Spark": "Webex",
        "com.hnc.Discord": "Discord",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.skype.skype": "Skype",
        "ru.keepcoder.Telegram": "Telegram",
    ]

    static let browsers: [String: String] = [
        "com.google.Chrome": "Chrome",
        "com.apple.Safari": "Safari",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "Brave",
        "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "Opera",
    ]

    /// Processes that capture for an app but do not carry its bundle ID.
    static let hosts: [String: String] = [
        "com.apple.WebKit.GPU": "com.apple.Safari",
        "avconferenced": "com.apple.FaceTime",
    ]

    /// Parts of the window title of a browser tab that is in a call.
    static let meetingTitles = ["meet –", "meet -", "google meet", "zoom meeting", "zoom webinar", "microsoft teams", "| teams", "webex", "jitsi", "whereby"]

    /// The app that a process belongs to. A helper process carries its
    /// app's bundle ID with a suffix, for example "com.google.Chrome.helper".
    static func app(forProcess identifier: String) -> MeetingCallApp? {
        if let bundleID = hosts[identifier] {
            return app(bundleID: bundleID)
        }
        let bundleID = (Array(callApps.keys) + Array(browsers.keys)).first { identifier == $0 || identifier.hasPrefix($0 + ".") }
        return bundleID.flatMap(app(bundleID:))
    }

    static func titleShowsMeeting(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return meetingTitles.contains { lowered.contains($0) }
    }

    private static func app(bundleID: String) -> MeetingCallApp? {
        if let name = callApps[bundleID] {
            return MeetingCallApp(name: name, bundleID: bundleID, isBrowser: false)
        }
        return browsers[bundleID].map { MeetingCallApp(name: $0, bundleID: bundleID, isBrowser: true) }
    }
}

/// A call app or browser that holds the microphone, as one read sees it.
struct MicrophoneUser: Equatable, Sendable {
    let app: MeetingCallApp
    let playsOutput: Bool
}

/// When calls start and end, from reads of the call apps and browsers that
/// hold the microphone.
///
/// - An app's use of the microphone becomes a call after `callAppDelay`: for
///   a call app, or a browser whose window title names a call service. Any
///   other browser needs `browserDelay`.
/// - A call ends when its app releases the microphone.
/// - While a meeting records, it follows one call: the call it started
///   for, or else a call that goes on at its start or starts later. That
///   call also ends when its app plays no sound for `silentCallLimit`.
struct MeetingCallWatch {
    static let callAppDelay: TimeInterval = 2
    static let browserDelay: TimeInterval = 20
    static let silentCallLimit: TimeInterval = 120

    enum Event: Equatable {
        /// A call started while no meeting records. `confirmed` is false for
        /// a browser whose window title names no call service.
        case callStarted(MeetingCallApp, confirmed: Bool)
        /// The recording follows this call from now on.
        case followed(MeetingCallApp)
        /// A call that the recording does not follow ended.
        case callEnded(MeetingCallApp)
        /// The call that the recording follows ended at `endedAt`, on the
        /// clock of `update`: when its app released the microphone, or, when
        /// `silent`, played sound for the last time.
        case recordedCallEnded(MeetingCallApp, endedAt: TimeInterval, silent: Bool)
    }

    private struct Holder {
        let app: MeetingCallApp
        let since: TimeInterval
        var lastOutput: TimeInterval
        var isCall = false
    }

    private var holders: [String: Holder] = [:]
    private var isRecording = false
    private var recordedCall: MeetingCallApp?
    private var silentEndReported = false

    /// True while an app holds the microphone.
    var isWatching: Bool {
        !holders.isEmpty
    }

    /// True while an app's use of the microphone waits for its delay.
    var isTiming: Bool {
        holders.values.contains { !$0.isCall }
    }

    /// `call` is the call that the new recording is for, or nil.
    mutating func recordingStarted(call: MeetingCallApp?) -> [Event] {
        isRecording = true
        if let call {
            follow(call)
            return []
        }
        recordedCall = nil
        let calls = holders.values.filter(\.isCall)
        guard let first = calls.min(by: { ($0.app.isBrowser ? 1 : 0, $0.since) < ($1.app.isBrowser ? 1 : 0, $1.since) }) else { return [] }
        follow(first.app)
        return [.followed(first.app)]
    }

    mutating func recordingStopped() {
        isRecording = false
        recordedCall = nil
    }

    /// For a detector that stops reading: the next read starts every timer
    /// again.
    mutating func forgetHolders() {
        holders = [:]
    }

    /// `showsMeeting` reads a browser's window titles; it runs only for a
    /// browser whose use of the microphone is not a call yet.
    mutating func update(_ users: [MicrophoneUser], at now: TimeInterval, showsMeeting: (MeetingCallApp) -> Bool) -> [Event] {
        var events: [Event] = []
        let present = Set(users.map(\.app.bundleID))
        for (id, holder) in holders where !present.contains(id) {
            holders[id] = nil
            if recordedCall?.bundleID == id {
                recordedCall = nil
                events.append(.recordedCallEnded(holder.app, endedAt: now, silent: false))
            } else if holder.isCall {
                events.append(.callEnded(holder.app))
            }
        }
        for user in users {
            var holder = holders[user.app.bundleID] ?? Holder(app: user.app, since: now, lastOutput: now)
            if user.playsOutput {
                holder.lastOutput = now
            }
            if !holder.isCall {
                let confirmed = !user.app.isBrowser || showsMeeting(user.app)
                if now - holder.since >= (confirmed ? Self.callAppDelay : Self.browserDelay) {
                    holder.isCall = true
                    events += callStarted(user.app, confirmed: confirmed)
                }
            }
            holders[user.app.bundleID] = holder
        }
        if let call = recordedCall, !silentEndReported, let holder = holders[call.bundleID],
           now - holder.lastOutput >= Self.silentCallLimit {
            silentEndReported = true
            events.append(.recordedCallEnded(call, endedAt: holder.lastOutput, silent: true))
        }
        return events
    }

    private mutating func callStarted(_ app: MeetingCallApp, confirmed: Bool) -> [Event] {
        guard isRecording else { return [.callStarted(app, confirmed: confirmed)] }
        guard recordedCall == nil else { return [] }
        follow(app)
        return [.followed(app)]
    }

    private mutating func follow(_ app: MeetingCallApp) {
        recordedCall = app
        silentEndReported = false
    }
}
