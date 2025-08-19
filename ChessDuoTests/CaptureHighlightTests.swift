import Testing
@testable import ChessDuo

struct CaptureHighlightTests {
  // Scenario: simple position where white captures a black piece; ensure lastCapturedPieceID matches
  // and captured list contains that piece id immediately (live view / historyIndex == nil).
  @Test func liveCaptureHighlightAppears() async throws {
    // FEN: White rook on a1, black knight on a8; clear path vertical capture sequence (simplify by placing pieces)
    // We'll craft via FamousGame initialFEN with just those pieces plus kings.
    // FEN layout ranks 8..1: a8 knight black, a1 rook white; kings e1/e8.
    let fen = "r3k3/8/8/8/8/8/8/R3K3 w - - 0 1" // white rook a1 can not directly capture a8 (blocked by empty? needs vertical travel). Actually path is clear.
    let vm = GameViewModel()
    let game = FamousGame(title: "Capture Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil)
    vm.applyFamousGame(game, broadcast: false)
    // Move rook a1 -> a8 capturing knight
    let from = Square(file: 0, rank: 0) // a1
    let to = Square(file: 0, rank: 7)   // a8
    let ok = vm.makeLocalMove(from: from, to: to)
    #expect(ok, "Rook move a1->a8 should be legal")
    #expect(vm.lastCapturedPieceID != nil, "Expect capture recorded")
    #expect(vm.lastCaptureByMe == true)
    // The captured list for me should contain a black knight with that id
    let capturedIDs = Set(vm.capturedByMe.map { $0.id })
    #expect(capturedIDs.contains(vm.lastCapturedPieceID!), "Captured list should include captured piece id immediately")
  }
}
