import Foundation
@testable import ChessDuo

/// Test helpers shared across persistence / networking tests.
enum TestHelpers {
    /// Returns a brand new `GameViewModel` after removing any existing persisted game state file.
    static func freshCleanVM() -> GameViewModel {
        let probe = GameViewModel()
        let fileURL = probe.saveURL
        let dirURL = fileURL.deletingLastPathComponent()
        // Remove the whole test directory to ensure no stale ancillary files remain.
        try? FileManager.default.removeItem(at: dirURL)
        // Recreate by instantiating a new probe (which will lazily create directory on first save).
        return GameViewModel()
    }

    /// Constructs a remote move `NetMessage` with the given algebraic squares and origin identifier.
    /// Asserts (via fatalError) if squares are invalid to simplify test call sites.
    static func remoteMove(from: String, to: String, originID: String) -> NetMessage {
        guard let fromSq = Square(algebraic: from), let toSq = Square(algebraic: to) else {
            fatalError("Invalid square(s) provided to remoteMove helper: \(from)->\(to)")
        }
        var msg = NetMessage(kind: .move, move: Move(from: fromSq, to: toSq))
        msg.originID = originID
        return msg
    }
}
