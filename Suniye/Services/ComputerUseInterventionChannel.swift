import Foundation

final class ComputerUseInterventionChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String] = []

    func submit(_ instruction: String) {
        lock.withLock {
            pending.append(instruction)
        }
    }

    func takeAll() -> [String] {
        lock.withLock {
            defer { pending.removeAll(keepingCapacity: true) }
            return pending
        }
    }

    func removeAll() {
        lock.withLock {
            pending.removeAll(keepingCapacity: false)
        }
    }
}
