import Foundation

/// Keeps late recognizer callbacks and timeout callbacks from completing a newer session.
/// All calls belong on the main queue; audio callbacks capture the request separately.
final class RecognitionLifecycle {
    private var activeID: UUID?
    private(set) var isFinishing = false

    func begin() -> UUID {
        let id = UUID()
        activeID = id
        isFinishing = false
        return id
    }

    func accepts(_ id: UUID) -> Bool { activeID == id }

    func finish(_ id: UUID) {
        guard accepts(id) else { return }
        isFinishing = true
    }

    /// A normal completion and its fallback timeout must never run handlers twice.
    @discardableResult
    func complete(_ id: UUID) -> Bool {
        guard accepts(id) else { return false }
        activeID = nil
        isFinishing = false
        return true
    }
}
