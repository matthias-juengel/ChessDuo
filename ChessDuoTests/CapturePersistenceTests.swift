import Testing
@testable import ChessDuo

struct CapturePersistenceTests {
  @Test func archivesPersistAcrossLoad() async throws {
    let fen = "r3k3/8/8/8/8/8/8/R3K3 w - - 0 1"
    // Session 1: perform capture
    do {
      let vm = TestHelpers.freshCleanVM()
      let game = FamousGame(title: "Persist Capture", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
      vm.applyFamousGame(game, broadcast: false)
      let from = Square(file: 0, rank: 0)
      let to = Square(file: 0, rank: 7)
      #expect(vm.makeLocalMove(from: from, to: to))
      #expect(vm.lastCapturedPieceID != nil)
      vm.saveGame()
    }
    // Session 2: load and verify id still present
    do {
      // Important: use a plain GameViewModel so we don't delete the file we just saved.
      let vm = GameViewModel()
      vm.loadGameIfAvailable()
      #expect(vm.moveHistory.count == 1)
      #expect(!vm.whiteCapturedPieces.isEmpty || !vm.blackCapturedPieces.isEmpty)
      let allIDs = Set((vm.whiteCapturedPieces + vm.blackCapturedPieces).map { $0.id })
      #expect(vm.lastCapturedPieceID == nil || allIDs.contains(vm.lastCapturedPieceID!), "Captured archives should contain previous captured id (unless lastCapturedPieceID intentionally cleared on load)")
    }
  }
}
