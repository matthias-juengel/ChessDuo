import XCTest
@testable import ChessDuo

/// Tests to surface scenarios where both peers end up with the same color (both white or both black).
/// These simulate handshakes by exchanging NetMessages directly between two VMs without real PeerService transport.
final class ColorAssignmentTests: XCTestCase {
    // Helper to wire two VMs so send() just loops back immediately (bypassing PeerService).
    private func pair(_ a: GameViewModel, _ b: GameViewModel) {
        // We cannot easily replace PeerService internals here; instead we manually call handle() to simulate messages.
        // We'll emulate the minimal handshake: hello / proposeRole / acceptRole.
    }

    private func makePairedVMs() -> (GameViewModel, GameViewModel) {
        let a = TestHelpers.freshCleanVM()
        let b = TestHelpers.freshCleanVM()
        // Distinct stable IDs already ensured by init.
        return (a, b)
    }

    /// Scenario 1: Both peers start with nil myColor and exchange simultaneous hello messages (each carrying nil color).
    /// Expectation: One side proposes role (lexicographically smaller name -> white) and the other becomes black.
    func testSimultaneousHelloNoPreColor() throws {
        let (a, b) = makePairedVMs()
        a._testResetStableIdentity(to: UUID().uuidString)
        b._testResetStableIdentity(to: UUID().uuidString)
        // Force stable deterministic ordering of display names by overriding player names (simulate advertised names).
        a.playerName = "Alpha"
        b.playerName = "Zulu"
        // Simulate both sending hello with no color assigned yet.
        var helloA = NetMessage(kind: .hello)
        helloA.originID = a.stableOriginID
        var helloB = NetMessage(kind: .hello)
        helloB.originID = b.stableOriginID
        // Deliver concurrently (order could vary; test both orders)
        a.handle(helloB)
        b.handle(helloA)
        // After handling, at least one side should have proposed role automatically.
        // Trigger attemptRoleProposalIfNeeded explicitly (since real code calls it on peer change / hello fallthrough).
        a.attemptRoleProposalIfNeeded()
        b.attemptRoleProposalIfNeeded()
        // Exactly one white one black or one assigned and other nil awaiting later messages (fail if both same non-nil).
        if let ca = a.myColor, let cb = b.myColor {
            XCTAssertNotEqual(ca, cb, "Both peers ended up with same color after simultaneous hello (ca=\(ca) cb=\(cb))")
        } else {
            // At least one should now have proposed role.
            XCTAssert(a.myColor != nil || b.myColor != nil, "Neither peer assigned a color after handshake attempt")
        }
    }

    /// Scenario 2: Local peer sets itself white due to existing local moves before connection; remote joins later.
    /// Expectation: Remote becomes black after hello exchange.
    func testLocalHasMovesBeforeConnectionRemoteAdoptsOpposite() throws {
        let (a, b) = makePairedVMs()
        a._testResetStableIdentity(to: UUID().uuidString)
        b._testResetStableIdentity(to: UUID().uuidString)
        // a simulates prior local play: make a single white move to e4 so a sets itself white on connect logic.
        a.myColor = nil // start nil
    a.myColor = .white // emulate logic path (connection observer would do this if movesMade>0 & myColor nil)
        XCTAssertEqual(a.myColor, .white)
        // Remote b sends hello declaring it is black (expected) OR nil; a should respond to enforce roles.
        var helloB = NetMessage(kind: .hello, move: nil, color: b.myColor, deviceName: b.playerName)
        helloB.originID = b.stableOriginID
        a.handle(helloB)
        // a replies implicitly (in real network) with acceptRole; simulate b receiving acceptRole.
        var accept = NetMessage(kind: .acceptRole)
        accept.originID = a.stableOriginID
        b.handle(accept)
        XCTAssertEqual(a.myColor, .white)
        // Simulate b receiving a proposeRole from a (would have been sent earlier). Since a is white, b should become black.
        var propose = NetMessage(kind: .proposeRole)
        propose.originID = a.stableOriginID
        b.handle(propose)
        XCTAssertEqual(b.myColor, .black, "Remote should adopt black upon proposeRole when local was pre-white")
    }

    /// Scenario 3: Both peers already think they are white (possible after a reset race) then send hello; one should flip to black.
    func testBothWhiteAfterResetRaceHelloReconciliation() throws {
        let (a, b) = makePairedVMs()
        a._testResetStableIdentity(to: UUID().uuidString)
        b._testResetStableIdentity(to: UUID().uuidString)
        a.myColor = .white
        b.myColor = .white
        var helloA = NetMessage(kind: .hello, move: nil, color: a.myColor, deviceName: a.playerName)
        helloA.originID = a.stableOriginID
        var helloB = NetMessage(kind: .hello, move: nil, color: b.myColor, deviceName: b.playerName)
        helloB.originID = b.stableOriginID
        a.handle(helloB)
        b.handle(helloA)
        // Current logic section:
        // else if let mine = myColor, let remoteColor = msg.color, mine == remoteColor { ... }
        // If movesMade==0 and mine == .white it sets myColor = .black on the branch.
        // Expect one flips to black.
        let both = [a.myColor, b.myColor].compactMap { $0 }
        XCTAssertEqual(both.count, 2)
        XCTAssertNotEqual(a.myColor, b.myColor, "After reconciliation both peers still same color (white)")
    }
}
