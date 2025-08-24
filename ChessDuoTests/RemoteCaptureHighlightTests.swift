import Testing
import XCTest
@testable import ChessDuo

// Simulates a remote capture arriving via NetMessage(.move) and verifies highlighting state.
final class RemoteCaptureHighlightTests: XCTestCase {
  // Scenario: Remote (black) knight on b4 captures white pawn on d5 (constructed position).
  // We set local perspective to white; remote move should set lastCapturedPieceID and lastCaptureByMe=false.
  func testRemoteCaptureHighlightsOnReceiver() throws {
    let vmLocal = TestHelpers.freshCleanVM()
    // We'll assign local color AFTER loading the FEN so applyFamousGame doesn't overwrite or conflict.
    // Construct a simple board via FEN: white king e1, black king e8, white pawn d5, black knight b4
    // FEN ranks 8..1:
    // 8: 4k3
    // 7: 8
    // 6: 8
    // 5: 3P4  (white pawn d5)
    // 4: 1n6  (black knight b4)
    // 3: 8
    // 2: 8
    // 1: 4K3
  // Side to move must be black so the simulated incoming black capture is legal (was 'w' previously causing engine.tryMakeMove to fail).
  let fen = "4k3/8/8/3P4/1n6/8/8/4K3 b - - 0 1"
    let game = FamousGame(title: "Remote Capture", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
    vmLocal.applyFamousGame(game, broadcast: false)
  // Now force local POV to white (simulate negotiation outcome) so lastCaptureByMe logic evaluates from white perspective.
  vmLocal.myColor = .white
    // Simulate remote black knight capturing white pawn: Nb4xd5
    guard let from = Square(algebraic: "b4"), let to = Square(algebraic: "d5") else { return XCTFail("Bad squares") }
    var msg = NetMessage(kind: .move, move: Move(from: from, to: to))
    // Provide remote origin ID distinct from local
    msg.originID = "REMOTE-ORIGIN"
    // Provide deviceName fallback
    msg.deviceName = "RemotePlayer"
    vmLocal.handle(msg)
    // Assertions
    let capID = vmLocal.lastCapturedPieceID
    XCTAssertNotNil(capID, "Expect capture id recorded for remote capture")
    XCTAssertEqual(vmLocal.lastCaptureByMe, false, "Remote capture should set lastCaptureByMe=false")
    // Rebuild lists already executed; captured piece was white, so from white perspective it should appear in capturedByOpponent (opponent's captures list) if we model lists as perspective-relative.
    let allIDs = Set(vmLocal.capturedByOpponent.map { $0.id } + vmLocal.capturedByMe.map { $0.id })
    XCTAssertTrue(allIDs.contains(capID!), "Captured piece id must appear in at least one perspective list")
  }
}
