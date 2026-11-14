import Foundation

struct TimeoutError: LocalizedError {
    var errorDescription: String? { "timed out" }
}

/// Races `operation` against a deadline in a task group. A cancel of the caller
/// reaches the operation, and a deadline throws `TimeoutError` (never the
/// `CancellationError` or `URLError(.cancelled)` of the canceled operation).
/// Returns only after the operation stops, so the operation must honor
/// cancellation.
func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            throw TimeoutError()
        }
        defer {
            group.cancelAll()
        }
        return try await group.next()!
    }
}
