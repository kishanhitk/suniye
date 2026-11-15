import CryptoKit
import Foundation

enum ModelDownloadProgressEstimator {
    static func estimate(
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
        responseExpectedLength: Int64?,
        fallbackExpectedSize: Int64
    ) -> Double? {
        let expectedBytes: Int64
        if totalBytesExpectedToWrite > 0 {
            expectedBytes = totalBytesExpectedToWrite
        } else if let responseExpectedLength, responseExpectedLength > 0 {
            expectedBytes = responseExpectedLength
        } else if fallbackExpectedSize > 0 {
            expectedBytes = fallbackExpectedSize
        } else {
            return nil
        }

        guard totalBytesWritten >= 0 else {
            return nil
        }

        return min(max(Double(totalBytesWritten) / Double(expectedBytes), 0), 1)
    }
}

enum ModelDownloadSupport {
    /// Streams the file through SHA-256 in 4 MB reads; model files run to gigabytes.
    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
