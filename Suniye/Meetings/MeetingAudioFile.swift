import Foundation

/// One meeting track on disk: 16 kHz, mono, 16-bit PCM WAV. The writer
/// appends as audio arrives and rewrites the two size fields of the header
/// every few seconds, so a file cut by a crash loses at most that much audio
/// and `repairHeader(at:)` makes the rest readable.
enum MeetingAudioFormat {
    static let sampleRate = 16_000
    static let headerSize = 44
    static let bytesPerSample = 2
}

enum MeetingAudioFileError: LocalizedError, Equatable {
    case notAWaveFile(String)

    var errorDescription: String? {
        switch self {
        case let .notAWaveFile(name):
            return "\(name) is not a meeting audio file."
        }
    }
}

final class MeetingAudioFileWriter {
    let url: URL
    private let handle: FileHandle
    private let headerRefreshSamples: Int
    private var samplesWritten = 0
    private var samplesSinceHeaderRefresh = 0

    /// `headerRefreshSeconds` bounds how much audio a crash can cost.
    init(url: URL, headerRefreshSeconds: Double = 5) throws {
        self.url = url
        headerRefreshSamples = max(1, Int(headerRefreshSeconds * Double(MeetingAudioFormat.sampleRate)))
        FileManager.default.createFile(atPath: url.path, contents: Self.header(dataBytes: 0))
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    deinit {
        try? handle.close()
    }

    var durationSeconds: Double {
        Double(samplesWritten) / Double(MeetingAudioFormat.sampleRate)
    }

    /// `samples` are 16 kHz floats in -1...1; values outside are clipped.
    func append(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        var data = Data(count: samples.count * MeetingAudioFormat.bytesPerSample)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for (index, sample) in samples.enumerated() {
                let clipped = min(1, max(-1, sample))
                out[index] = Int16(clipped * Float(Int16.max)).littleEndian
            }
        }
        try handle.write(contentsOf: data)
        samplesWritten += samples.count
        samplesSinceHeaderRefresh += samples.count
        if samplesSinceHeaderRefresh >= headerRefreshSamples {
            try refreshHeader()
        }
    }

    func close() throws {
        try refreshHeader()
        try handle.synchronize()
        try handle.close()
    }

    private func refreshHeader() throws {
        let end = try handle.offset()
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Self.header(dataBytes: samplesWritten * MeetingAudioFormat.bytesPerSample))
        try handle.seek(toOffset: end)
        samplesSinceHeaderRefresh = 0
    }

    static func header(dataBytes: Int) -> Data {
        var data = Data()
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(MeetingAudioFormat.sampleRate))
        append(UInt32(MeetingAudioFormat.sampleRate * MeetingAudioFormat.bytesPerSample))
        append(UInt16(MeetingAudioFormat.bytesPerSample))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataBytes))
        return data
    }

    /// Rewrites the size fields from the real file length. Run on a file that
    /// a crash left behind before it is read.
    static func repairHeader(at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let length = Int(try handle.seekToEnd())
        guard length >= MeetingAudioFormat.headerSize else {
            throw MeetingAudioFileError.notAWaveFile(url.lastPathComponent)
        }
        let dataBytes = (length - MeetingAudioFormat.headerSize) / MeetingAudioFormat.bytesPerSample * MeetingAudioFormat.bytesPerSample
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header(dataBytes: dataBytes))
    }
}

enum MeetingAudioFileReader {
    /// Reads samples `range` (in samples) as floats. A range past the end is
    /// cut to the file.
    static func samples(at url: URL, range: Range<Int>? = nil) throws -> [Float] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: MeetingAudioFormat.headerSize) ?? Data()
        guard header.count == MeetingAudioFormat.headerSize, header.prefix(4) == Data("RIFF".utf8) else {
            throw MeetingAudioFileError.notAWaveFile(url.lastPathComponent)
        }
        let fileLength = Int(try handle.seekToEnd())
        let totalSamples = (fileLength - MeetingAudioFormat.headerSize) / MeetingAudioFormat.bytesPerSample
        let wanted = range ?? 0 ..< totalSamples
        let lower = min(max(0, wanted.lowerBound), totalSamples)
        let upper = min(max(lower, wanted.upperBound), totalSamples)
        guard upper > lower else { return [] }
        try handle.seek(toOffset: UInt64(MeetingAudioFormat.headerSize + lower * MeetingAudioFormat.bytesPerSample))
        let data = try handle.read(upToCount: (upper - lower) * MeetingAudioFormat.bytesPerSample) ?? Data()
        return data.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / Float(Int16.max) }
        }
    }

    static func sampleCount(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return max(0, size - MeetingAudioFormat.headerSize) / MeetingAudioFormat.bytesPerSample
    }
}
