import Foundation

/// Delegate callbacks may arrive outside Swift concurrency. Preserve their order
/// while explicitly hopping to the main actor; never assert actor isolation.
final class DownloadEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?
    func enqueue(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        lock.lock()
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
        lock.unlock()
    }
}

enum DownloadRecovery {
    enum Action { case keep, finish, interrupt }
    static func action(active: Bool, queued: Bool, completed: Bool, failed: Bool,
                       savedFileExists: Bool, finalizedMP4: Bool) -> Action {
        if active || completed || failed { return .keep }
        if savedFileExists && finalizedMP4 { return .finish }
        if queued { return .keep }
        return .interrupt
    }
}
