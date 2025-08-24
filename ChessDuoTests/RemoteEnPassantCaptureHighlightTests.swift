import Testing
import XCTest
@testable import ChessDuo

// Validates remote en passant capture triggers correct highlight + archives.
final class RemoteEnPassantCaptureHighlightTests: XCTestCase {
  // Position: White pawn on e5 (e5 square: file=4 rank=4), black pawn on d7 (d7 file=3 rank=6). It's black to move.
  // Sequence we simulate for remote side (black): 1... d5 (black pawn two-step from d7 to d5) then local engine now has en passant square.
  // Remote then sends en passant capture exd6 ep: white pawn from e5 captures pawn that moved two squares (landing on d6).
  // We simulate this by first applying the black double pawn move locally via handle(.move), then another remote move from e5->d6.
  func testRemoteEnPassantCaptureHighlight() throws {
    // Suppress real networking noise.
    PeerService.suppressNetworking = true
    let vm = TestHelpers.freshCleanVM()
    // POV: we are black so the subsequent remote white en passant capture should set lastCaptureByMe=false.
    vm.myColor = .black
    // FEN layout (black to move): white king e1, black king e8, white pawn e5, black pawn d7
    // 8: 4k3
    // 7: 3p4
    // 6: 8
    // 5: 4P3
    // 4: 8
    // 3: 8
    // 2: 8
    // 1: 4K3
    let fen = "4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1"
    let game = FamousGame(title: "En Passant Remote", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
    vm.applyFamousGame(game, broadcast: false)

    // Step 1: Remote black plays d7-d5 (double pawn push) -> enables en passant for white pawn e5 to capture d6.
    guard let d7 = Square(algebraic: "d7"), let d5 = Square(algebraic: "d5") else { return XCTFail("Bad squares d7/d5") }
    var first = NetMessage(kind: .move, move: Move(from: d7, to: d5))
    first.originID = "REMOTE-ENP"
    vm.handle(first)

    // Sanity: last move should now be d7-d5 and side to move white.
    XCTAssertEqual(vm.engine.sideToMove, .white, "Expected white to move after remote black double push")

    // Step 2: Remote sends en passant capture e5xd6 ep (from e5 to d6 capturing pawn that moved two squares).
    guard let e5 = Square(algebraic: "e5"), let d6 = Square(algebraic: "d6") else { return XCTFail("Bad squares e5/d6") }
    var epMsg = NetMessage(kind: .move, move: Move(from: e5, to: d6))
    epMsg.originID = "REMOTE-ENP"
    vm.handle(epMsg)

    // Validate capture metadata.
    let capID = vm.lastCapturedPieceID
    XCTAssertNotNil(capID, "Expect en passant captured piece id recorded")
  XCTAssertEqual(vm.lastCaptureByMe, false, "Capture performed by opponent (remote white) from our black POV")
    // The captured pawn was black, so from white POV it should appear in capturedByMe list.
    let blackArchived = vm.blackCapturedPieces.contains { $0.id == capID }
    XCTAssertTrue(blackArchived, "Black pawn should be archived among blackCapturedPieces with real id")
  }
}
