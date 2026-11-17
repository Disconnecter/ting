import Foundation

/// Shared by nested libraries, so a question pauses all enclosing execution budgets.
final class MicroAppWaitingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0

    var elapsed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return seconds
    }

    func add(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        seconds += interval
    }
}
