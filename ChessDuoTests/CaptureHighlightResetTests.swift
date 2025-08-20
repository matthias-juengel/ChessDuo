//import Testing
//@testable import ChessDuo
//
//struct CaptureHighlightResetTests {
//  @Test func highlightPersistsAcrossReset() async throws {
//    let vm = GameViewModel()
//    // Force single-device mode perspective consistency
//    vm.preferredPerspective = .white
//
//  // Make an opening capture sequence: 1. e4 d5 2. exd5
//  // Sequence: white pawn e2->e4, black pawn d7->d5, white pawn e4xd5 captures.
//    // Execute moves directly in local mode.
//    func move(_ from: String, _ to: String) {
//      guard let f = Square(algebraic: from), let t = Square(algebraic: to) else {
//        #expect(Bool(false), "Bad algebraic square")
//        return
//      }
//      #expect(vm.makeLocalMove(from: f, to: t))
//    }
//  move("e2","e4")
//  move("d7","d5")
//    move("e4","d5") // capture black pawn
//    // After capture, lastCapturedPieceID should be non-nil and belong to black.
//    let firstCaptureID = try #require(vm.lastCapturedPieceID)
//    #expect(vm.lastCaptureByMe == true) // single-device: white captured
//
//    // Reset game
//    vm.performLocalReset(send: false)
//    #expect(vm.lastCapturedPieceID == nil)
//    #expect(vm.whiteCapturedPieces.isEmpty)
//    #expect(vm.blackCapturedPieces.isEmpty)
//
//  // Perform a new independent capture: 1. d4 e5 2. dxe5
//  move("d2","d4")
//  move("e7","e5")
//    move("d4","e5") // white pawn captures black pawn
//    let secondCaptureID = try #require(vm.lastCapturedPieceID)
//    #expect(secondCaptureID != firstCaptureID) // new piece
//    #expect(vm.lastCaptureByMe == true)
//  }
//}
