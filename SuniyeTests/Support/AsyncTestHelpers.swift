import Foundation
import XCTest

/// One-shot gate for holding an async stub call open until the test releases it.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        let pending = waiters
        waiters = []
        isOpen = true
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

/// Polls `condition` on the main actor and fails the test at the call site if it is still false after `timeout`.
@MainActor
func waitUntil(
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition(), "condition still false after \(timeout) s", file: file, line: line)
}

/// Yields the main actor so tasks it already scheduled can run their next step.
@MainActor
func drainScheduledTasks(yields: Int = 8) async {
    for _ in 0 ..< yields {
        await Task.yield()
    }
}
