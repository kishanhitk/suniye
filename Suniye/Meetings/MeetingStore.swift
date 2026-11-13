import Foundation

/// Meetings on disk, one folder per meeting:
///
///     meetings/<id>/meeting.json    the record
///     meetings/<id>/segments.jsonl  one transcript segment per line, appended as each finishes
///     meetings/<id>/notes.txt       the user's notes
///     meetings/<id>/summary.md      the summary
///     meetings/<id>/you.wav         microphone track
///     meetings/<id>/them.wav        call audio track
///
/// Appends and small atomic writes keep a crash from losing more than the
/// segment in flight.
actor MeetingStore {
    enum StoreError: LocalizedError, Equatable {
        case unknownMeeting(UUID)

        var errorDescription: String? {
            switch self {
            case let .unknownMeeting(id):
                return "No meeting \(id.uuidString) on disk."
            }
        }
    }

    static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)
    }

    nonisolated let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootDirectory: URL = MeetingStore.defaultRootDirectory(), fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

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

    func save(_ record: MeetingRecord) throws {
        guard fileManager.fileExists(atPath: folder(for: record.id).path) else {
            throw StoreError.unknownMeeting(record.id)
        }
        try encoder.encode(record).write(to: recordURL(record.id), options: .atomic)
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

    func appendSegment(_ segment: MeetingSegment, to id: UUID) throws {
        guard fileManager.fileExists(atPath: folder(for: id).path) else {
            throw StoreError.unknownMeeting(id)
        }
        var line = try encoder.encode(segment)
        line.append(0x0A)
        let url = segmentsURL(id)
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
    func replaceSegments(_ segments: [MeetingSegment], of id: UUID) throws {
        guard fileManager.fileExists(atPath: folder(for: id).path) else {
            throw StoreError.unknownMeeting(id)
        }
        var data = Data()
        for segment in segments {
            data.append(try encoder.encode(segment))
            data.append(0x0A)
        }
        try data.write(to: segmentsURL(id), options: .atomic)
    }

    /// In time order. A line cut by a crash is skipped.
    func segments(of id: UUID) -> [MeetingSegment] {
        guard let data = try? Data(contentsOf: segmentsURL(id)) else { return [] }
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

    func notes(of id: UUID) -> String {
        (try? String(contentsOf: notesURL(id), encoding: .utf8)) ?? ""
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

    func hasAudio(of id: UUID) -> Bool {
        MeetingTrack.allCases.contains { fileManager.fileExists(atPath: audioURL($0, for: id).path) }
    }

    func deleteAudio(of id: UUID) {
        for track in MeetingTrack.allCases {
            try? fileManager.removeItem(at: audioURL(track, for: id))
        }
    }

    func delete(_ id: UUID) throws {
        let url = folder(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Repairs the audio headers of every meeting that a quit or crash left
    /// mid-session, and returns them. A meeting that was recording or paused
    /// moves to `.finishing`, and the app finishes its transcript; one that
    /// was finishing moves to `.interrupted`.
    func recoverInterruptedMeetings() -> [MeetingRecord] {
        var recovered: [MeetingRecord] = []
        for var record in loadAll() where record.status.needsRecovery {
            var audioSamples = 0
            for track in MeetingTrack.allCases where fileManager.fileExists(atPath: audioURL(track, for: record.id).path) {
                do {
                    try MeetingAudioFileWriter.repairHeader(at: audioURL(track, for: record.id))
                    audioSamples = max(audioSamples, try MeetingAudioFileReader.sampleCount(at: audioURL(track, for: record.id)))
                } catch {
                    AppLogger.shared.log(.warning, "meeting recovery could not repair audio id=\(record.id.uuidString) track=\(track.rawValue) error=\(error.localizedDescription)")
                }
            }
            record.status = record.status == .finishing ? .interrupted : .finishing
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

    private func recordURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("meeting.json")
    }

    private func segmentsURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("segments.jsonl")
    }

    private func notesURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("notes.txt")
    }

    private func summaryURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("summary.md")
    }
}
