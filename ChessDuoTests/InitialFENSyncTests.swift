import XCTest
@testable import ChessDuo

final class InitialFENSyncTests: XCTestCase {
    func testApplyingLoadGameStateWithInitialFENSetsBaseline() throws {
        let vm = GameViewModel()
        // Prepare a custom FEN (rook mate net sample) and a minimal famous game snapshot with no moves
        let fen = "8/8/8/8/3k4/8/4K3/4R3 w - - 0 1"
        // Decode FEN to board so we can craft message fields
        guard let engineFromFEN = ChessEngine.fromFEN(fen) else { return XCTFail("FEN parse failed") }
        // Build message emulating remote loadGameState broadcast
        let msg = NetMessage(kind: .loadGameState,
                             move: nil,
                             color: nil,
                             deviceName: "Tester",
                             board: engineFromFEN.board,
                             sideToMove: engineFromFEN.sideToMove,
                             movesMade: 0,
                             capturedByMe: [],
                             capturedByOpponent: [],
                             lastMoveFrom: nil,
                             lastMoveTo: nil,
                             lastCapturedPieceID: nil,
                             lastCaptureByMe: nil,
                             moveHistory: [],
                             revertToCount: nil,
                             historyViewIndex: nil,
                             gameTitle: "K+R vs K Technique",
                             initialFEN: fen)
        vm.handle(msg)
        // Assert baseline was set using FEN (rook on e1, kings on e2/d4 positions) and side to move white.
        let rookSquare = Square(file: 4, rank: 0)
        XCTAssertEqual(vm.baselineBoard.piece(at: rookSquare)?.type, .rook)
        XCTAssertEqual(vm.baselineBoard.piece(at: Square(file: 4, rank: 1))?.type, .king) // white king e2
        XCTAssertEqual(vm.baselineBoard.piece(at: Square(file: 3, rank: 3))?.type, .king) // black king d4
        XCTAssertEqual(vm.baselineSideToMove, .white)
    }
}
