//
//  ChessDuoTests.swift
//  ChessDuoTests
//
//  Created by Matthias Jüngel on 10.08.25.
//

import Testing
@testable import ChessDuo

struct ChessDuoTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func pgnParsingBasicOpen() async throws {
        let pgn = "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6"
        let result = PGNParser.parseMoves(pgn: pgn)
        switch result {
        case .success(let moves):
            // Sequence has exactly 4 full moves: (e4 e5) (Nf3 Nc6) (Bb5 a6) (Ba4 Nf6) = 8 half-moves
            #expect(moves.count == 8, "Expected 8 half-moves, got \(moves.count)")
            var engine = ChessEngine()
            moves.forEach { _ = engine.tryMakeMove($0) }
            // After Nf6, it is White to move (even count)
            #expect(engine.sideToMove == .white)
            // Last move should end with black knight on f6
            let f6 = Square(file: 5, rank: 5) // f6 -> file 5 rank 5 (0-based ranks)
            let piece = engine.board.piece(at: f6)
            #expect(piece?.type == .knight && piece?.color == .black)
        case .failure(let err):
            #expect(Bool(false), "PGN parse failed: \(err)")
        }
    }

    @Test func pgnParsingCompactTokens() async throws {
        // Same moves but with compact tokens like 1.e4 and no spaces before SAN
        let pgn = "1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 4.Ba4 Nf6"
        let result = PGNParser.parseMoves(pgn: pgn)
        switch result {
        case .success(let moves):
            #expect(moves.count == 8, "Expected 8 half-moves, got \(moves.count)")
            var engine = ChessEngine()
            moves.forEach { _ = engine.tryMakeMove($0) }
            #expect(engine.sideToMove == .white)
        case .failure(let err):
            #expect(Bool(false), "PGN parse failed (compact): \(err)")
        }
    }

    // MARK: - Captured Pieces Baseline/FEN Tests


    @Test func capturedListsRemainEmptyInKQvKScenario() async throws {
        let fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1" // KQ vs K
        let vm = GameViewModel()
        let game = FamousGame(title: "KQvK Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil)
        vm.applyFamousGame(game, broadcast: false)
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Captured lists should be empty initially for KQvK FEN")
    }

    @Test func noPhantomCapturesAfterNonCaptureMoveInKQvK() async throws {
        let fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1"
        let vm = GameViewModel()
        let game = FamousGame(title: "KQvK Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil)
        vm.applyFamousGame(game, broadcast: false)
        // Find the queen at d2 (file 3 rank 1) and move it to e2 (file 4 rank 1) if legal (horizontal slide)
        let from = Square(file: 3, rank: 1)
        let to = Square(file: 4, rank: 1)
        // Attempt move (white to move)
        _ = vm.makeLocalMove(from: from, to: to)
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Captured lists should still be empty after quiet queen move")
        // Simulate history slider: go back to 0 then forward to 1
        vm.historyIndex = 0
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Captured lists should be empty at historyIndex 0")
        vm.historyIndex = 1
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Captured lists should be empty at historyIndex 1")
    }

    @Test func revertHistoryKeepsCapturedListsEmptyInKQvK() async throws {
        let fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1"
        let vm = GameViewModel()
        let game = FamousGame(title: "KQvK Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil)
        vm.applyFamousGame(game, broadcast: false)
        // Quiet move
        let from = Square(file: 3, rank: 1)
        let to = Square(file: 4, rank: 1)
        _ = vm.makeLocalMove(from: from, to: to)
        #expect(vm.moveHistory.count == 1)
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Captured lists should be empty after quiet move")
        // Revert to 0
        vm.performHistoryRevert(to: 0, send: false)
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Captured lists should remain empty after revert")
    }

    @Test func loadingRealKQvKMateAfterResetShowsNoCaptures() async throws {
        let vm = GameViewModel()
        vm.performLocalReset(send: false) // explicit New Game
        #expect(vm.moveHistory.isEmpty && vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty)
        let games = FamousGamesLoader.shared.getAllGames()
        guard let realGame = games.first(where: { $0.title == "K+Q vs K Mate" }) else {
            #expect(Bool(false), "'K+Q vs K Mate' not found in FamousGames.json")
            return
        }
        vm.applyFamousGame(realGame, broadcast: false)
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "No captures expected immediately after loading K+Q vs K Mate")
    // Quiet queen move Qe1->Qf2 (diagonal; f2 is empty in baseline FEN) ensures legality
    let from = Square(file: 4, rank: 0) // e1
    let to = Square(file: 5, rank: 1)   // f2
    let moveOk = vm.makeLocalMove(from: from, to: to)
    #expect(moveOk, "Expected queen move e1->f2 to be legal")
    #expect(vm.moveHistory.count == 1, "Move history should have exactly 1 move after quiet queen move")
    #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Quiet queen move must not introduce captures")
    // Black king reply: from d4 (file 3 rank 3) to e4 (file 4 rank 3)
    let blackFrom = Square(file: 3, rank: 3) // d4
    let blackTo = Square(file: 4, rank: 3) // e4
    let blackMoveOk = vm.makeLocalMove(from: blackFrom, to: blackTo)
    #expect(blackMoveOk, "Expected black king move d4->e4 to be legal")
    #expect(vm.moveHistory.count == 2, "After two quiet moves history count should be 2")
    #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Still no captures after black reply")
    // History indices: 0 (initial), 1 (after white move), 2 (after black move)
    vm.historyIndex = 0
    #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "History index 0 should have no captures")
    vm.historyIndex = 1
    #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "History index 1 should have no captures")
    vm.historyIndex = 2
    #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "History index 2 should have no captures")
    // Return to live
    vm.historyIndex = nil
    #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Live view should still have no captures")
    }
}
