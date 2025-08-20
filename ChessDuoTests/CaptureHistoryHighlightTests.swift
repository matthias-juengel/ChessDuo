import Testing
@testable import ChessDuo

struct CaptureHistoryHighlightTests {
  @Test func historicalHighlightUsesCapturedPieceID() async throws {
    // Position enabling immediate capture: white rook a1, black knight a8, kings present.
    let fen = "r3k3/8/8/8/8/8/8/R3K3 w - - 0 1"
    let vm = GameViewModel()
    let game = FamousGame(title: "History Capture", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil)
    vm.applyFamousGame(game, broadcast: false)
    let from = Square(file: 0, rank: 0)
    let to = Square(file: 0, rank: 7)
    #expect(vm.makeLocalMove(from: from, to: to))
    let capID = vm.lastCapturedPieceID
    #expect(capID != nil)
    // Move history now has 1 move; historyIndex=1 means viewing after that move.
    vm.historyIndex = 1
    let ctx = vm.captureReconstruction(at: 1)
    // lastCapturePieceID of reconstruction at index 1 should equal recorded capture
    #expect(ctx.lastCapturePieceID == capID, "Reconstruction lastCapturePieceID should match recorded id")
    // Ensure the captured piece id appears in the appropriate archive list (perspective agnostic check)
    let allArchived = vm.whiteCapturedPieces + vm.blackCapturedPieces
    #expect(allArchived.contains { $0.id == capID })
  }

//  @Test func captureHighlightDoesNotPersistAfterQuietFollowup() async throws {
//    // Scenario: initial capture then a quiet reply. History highlighting should show only at index of capture (position after capture move), not after subsequent quiet move.
//    // FEN sets up immediate white capture: white rook a1, black knight a8, plus kings.
//    let fen = "r3k3/8/8/8/8/8/8/R3K3 w - - 0 1"
//    let vm = GameViewModel()
//    let game = FamousGame(title: "Capture Then Quiet", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil)
//    vm.applyFamousGame(game, broadcast: false)
//    // White captures: Ra1xa8
//    let from = Square(file: 0, rank: 0)
//    let to = Square(file: 0, rank: 7)
//    #expect(vm.makeLocalMove(from: from, to: to))
//    #expect(vm.lastCapturedPieceID != nil)
//    // Black makes a quiet king move (e8->d8) to avoid any further capture.
//    let bkFrom = Square(file: 4, rank: 7)
//    let bkTo = Square(file: 3, rank: 7)
//    #expect(vm.makeLocalMove(from: bkFrom, to: bkTo))
//    #expect(vm.moveHistory.count == 2)
//    // historyIndex = 1 (after first move) should indicate a capture highlight exists.
//    #expect(vm.historicalCaptureHighlight(at: 1) != nil, "Expected capture highlight at index 1")
//    // historyIndex = 2 (after second move) should NOT highlight capture.
//    #expect(vm.historicalCaptureHighlight(at: 2) == nil, "Capture highlight should not persist after non-capturing reply")
//  }
}
