import Foundation

/// Meetings on disk, one folder per meeting; docs/MEETINGS.md lists the
/// files. Appends and small atomic writes keep a crash from losing more than
/// the segment in flight.
actor MeetingStore {
    /// The lines of a meeting: its transcript, or the draft that Transcribe
    /// Again writes. The draft replaces the transcript only when it is
    /// complete.
    enum SegmentFile: Sendable {
        case transcript
        case draft
    }

    enum StoreError: LocalizedError, Equatable {
        case unknownMeeting(UUID)

        var errorDescription: String? {
            switch self {
            case let .unknownMeeting(id):
                return "No meeting \(id.uuidString) on disk."
            }
        }
    }

    static let supportDirectory: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory)
        .appendingPathComponent("Suniye", isDirectory: true)

    /// One folder per app: Stable and Preview run side by side, and each one
    /// recovers the recordings that it finds at launch.
    static func defaultRootDirectory(identity: AppIdentity = .current) -> URL {
        supportDirectory.appendingPathComponent(identity.isPreview ? "meetings-preview" : "meetings", isDirectory: true)
    }

    nonisolated let rootDirectory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootDirectory: URL = MeetingStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.dateStyle))
        }
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Self.dateStyle.parse(decoder.singleValueContainer().decode(String.self))
        }
    }

    /// Times keep their milliseconds: the recorded time and the pauses count
    /// from `startedAt`.
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    nonisolated func folder(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    nonisolated func audioURL(_ track: MeetingTrack, for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("\(track.rawValue).wav")
    }

    func create(_ record: MeetingRecord) throws {
        try fileManager.createDirectory(at: folder(for: record.id), withIntermediateDirectories: true)
        try save(record)
    }

    private func save(_ record: MeetingRecord) throws {
        guard fileManager.fileExists(atPath: folder(for: record.id).path) else {
            throw StoreError.unknownMeeting(record.id)
        }
        try encoder.encode(record).write(to: recordURL(record.id), options: .atomic)
    }

    /// Reads, changes and writes the record in one step, so two writers
    /// cannot lose each other's change.
    @discardableResult
    func update(_ id: UUID, _ change: (inout MeetingRecord) -> Void) throws -> MeetingRecord {
        guard var record = record(id) else {
            throw StoreError.unknownMeeting(id)
        }
        change(&record)
        try save(record)
        return record
    }

    func record(_ id: UUID) -> MeetingRecord? {
        guard let data = try? Data(contentsOf: recordURL(id)) else { return nil }
        return try? decoder.decode(MeetingRecord.self, from: data)
    }

    /// Newest first. A folder with an unreadable record is skipped and logged,
    /// never deleted.
    func loadAll() -> [MeetingRecord] {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var records: [MeetingRecord] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            if let record = record(id) {
                records.append(record)
            } else {
                AppLogger.shared.log(.warning, "meeting store skipped unreadable record folder=\(folder.lastPathComponent)")
            }
        }
        return records.sorted { $0.startedAt > $1.startedAt }
    }

    func appendSegment(_ segment: MeetingSegment, to id: UUID, in file: SegmentFile = .transcript) throws {
        guard fileManager.fileExists(atPath: folder(for: id).path) else {
            throw StoreError.unknownMeeting(id)
        }
        var line = try encoder.encode(segment)
        line.append(0x0A)
        let url = segmentsURL(id, file)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    /// Replaces every segment, for example after the echo filter ran over the
    /// whole meeting.
    func replaceSegments(_ segments: [MeetingSegment], of id: UUID, in file: SegmentFile = .transcript) throws {
        guard fileManager.fileExists(atPath: folder(for: id).path) else {
            throw StoreError.unknownMeeting(id)
        }
        var data = Data()
        for segment in segments {
            data.append(try encoder.encode(segment))
            data.append(0x0A)
        }
        try data.write(to: segmentsURL(id, file), options: .atomic)
    }

    /// The draft becomes the transcript.
    func keepDraft(of id: UUID) throws {
        let draft = segmentsURL(id, .draft)
        let transcript = segmentsURL(id, .transcript)
        if fileManager.fileExists(atPath: transcript.path) {
            _ = try fileManager.replaceItemAt(transcript, withItemAt: draft)
        } else {
            try fileManager.moveItem(at: draft, to: transcript)
        }
    }

    func deleteDraft(of id: UUID) {
        try? fileManager.removeItem(at: segmentsURL(id, .draft))
    }

    /// In time order. A line cut by a crash is skipped.
    func segments(of id: UUID, in file: SegmentFile = .transcript) -> [MeetingSegment] {
        guard let data = try? Data(contentsOf: segmentsURL(id, file)) else { return [] }
        var segments: [MeetingSegment] = []
        var skipped = 0
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let segment = try? decoder.decode(MeetingSegment.self, from: Data(line)) {
                segments.append(segment)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 {
            AppLogger.shared.log(.warning, "meeting store skipped unreadable segments id=\(id.uuidString) count=\(skipped)")
        }
        return MeetingTranscript.ordered(segments)
    }

    /// "" when the meeting has no notes; nil when the file cannot be read.
    func notes(of id: UUID) -> String? {
        let url = notesURL(id)
        guard fileManager.fileExists(atPath: url.path) else { return "" }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveNotes(_ text: String, for id: UUID) throws {
        guard fileManager.fileExists(atPath: folder(for: id).path) else {
            throw StoreError.unknownMeeting(id)
        }
        try text.write(to: notesURL(id), atomically: true, encoding: .utf8)
    }

    func summary(of id: UUID) -> String? {
        try? String(contentsOf: summaryURL(id), encoding: .utf8)
    }

    func saveSummary(_ text: String, for id: UUID) throws {
        guard fileManager.fileExists(atPath: folder(for: id).path) else {
            throw StoreError.unknownMeeting(id)
        }
        try text.write(to: summaryURL(id), atomically: true, encoding: .utf8)
    }

    func diskUsage() -> Int64 {
        guard let files = fileManager.enumerator(at: rootDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    /// The tracks whose audio file is still on disk.
    nonisolated func audioTracks(of id: UUID) -> [MeetingTrack] {
        MeetingTrack.allCases.filter { FileManager.default.fileExists(atPath: audioURL($0, for: id).path) }
    }

    /// True when no audio of the meeting is left.
    @discardableResult
    func deleteAudio(of id: UUID) -> Bool {
        for track in audioTracks(of: id) {
            do {
                try fileManager.removeItem(at: audioURL(track, for: id))
            } catch {
                AppLogger.shared.log(.error, "meeting audio not deleted id=\(id.uuidString) track=\(track.rawValue) error=\(error.localizedDescription)")
            }
        }
        return audioTracks(of: id).isEmpty
    }

    func delete(_ id: UUID) throws {
        let url = folder(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Repairs the audio headers of every meeting that a quit or crash left
    /// mid-session, and returns them. A meeting that was recording or paused
    /// moves to `.notTranscribed`; one that was finishing moves to
    /// `.interrupted`. Both wait for Finish Transcript. A draft that a quit
    /// or a crash cut short goes, and the transcript stays.
    func recoverInterruptedMeetings() -> [MeetingRecord] {
        var recovered: [MeetingRecord] = []
        for var record in loadAll() {
            deleteDraft(of: record.id)
            guard record.status.needsRecovery else { continue }
            var audioSamples = 0
            for track in MeetingTrack.allCases where fileManager.fileExists(atPath: audioURL(track, for: record.id).path) {
                do {
                    try MeetingAudioFileWriter.repairHeader(at: audioURL(track, for: record.id))
                    audioSamples = max(audioSamples, try MeetingAudioFileReader.sampleCount(at: audioURL(track, for: record.id)))
                } catch {
                    AppLogger.shared.log(.warning, "meeting recovery could not repair audio id=\(record.id.uuidString) track=\(track.rawValue) error=\(error.localizedDescription)")
                }
            }
            cutTornSegment(of: record.id)
            record.status = record.status == .finishing ? .interrupted : .notTranscribed
            // A pause that never ended has no audio after it, so it moves no
            // audio position and only blurs the meeting length.
            if let lastPause = record.pauses.last, lastPause.end == nil {
                record.pauses.removeLast()
            }
            if record.endedAt == nil {
                let audioSeconds = Double(audioSamples) / Double(MeetingAudioFormat.sampleRate)
                let wallSeconds = MeetingTimeline(pauses: record.pauses).wallSeconds(forAudioSeconds: audioSeconds)
                record.endedAt = record.startedAt.addingTimeInterval(wallSeconds)
            }
            do {
                try save(record)
                recovered.append(record)
            } catch {
                AppLogger.shared.log(.error, "meeting recovery could not save id=\(record.id.uuidString) error=\(error.localizedDescription)")
            }
        }
        return recovered
    }

    /// A crash during a write can leave a line with no end. A line appended
    /// after it would join it and be lost on read, so the torn part goes.
    private func cutTornSegment(of id: UUID) {
        let url = segmentsURL(id, .transcript)
        guard let data = fileManager.contents(atPath: url.path), let last = data.last, last != 0x0A else { return }
        let keep = (data.lastIndex(of: 0x0A).map { $0 + 1 }) ?? 0
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(keep))
        } catch {
            AppLogger.shared.log(.warning, "meeting recovery could not cut a torn segment id=\(id.uuidString) error=\(error.localizedDescription)")
        }
    }

    private func recordURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("meeting.json")
    }

    private func segmentsURL(_ id: UUID, _ file: SegmentFile) -> URL {
        switch file {
        case .transcript:
            return folder(for: id).appendingPathComponent("segments.jsonl")
        case .draft:
            return folder(for: id).appendingPathComponent("segments-draft.jsonl")
        }
    }

    private func notesURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("notes.txt")
    }

    private func summaryURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("summary.md")
    }
}
