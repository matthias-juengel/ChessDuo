//
//  ChessDuoTests.swift
//  ChessDuoTests
//
//  Created by Matthias Jüngel on 10.08.25.
//
// Example test command
/// xcodebuild test -project ChessDuo.xcodeproj -scheme ChessDuo -testPlan ChessDuoUnitTest -destination 'id=D77147FD-9784-450E-A13F-C194B7AD0D16' > full_test_output.txt 2>&1; tail -n 200 full_test_output.txt



import Testing
@testable import ChessDuo
import Foundation

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

    // MARK: - Category Grouping Tests
    @Test func famousGamesAreGroupedByCategory() async throws {
        let loader = FamousGamesLoader.shared
        let all = loader.getAllGames()
        let groups = loader.gamesGroupedByCategory(locale: Locale(identifier: "en"))
        // Ensure every game appears exactly once across groups
        let totalFromGroups = groups.reduce(0) { $0 + $1.games.count }
        #expect(totalFromGroups == all.count, "Grouped games total (\(totalFromGroups)) should match all games count (\(all.count))")
        // Ensure no empty groups are produced
        #expect(groups.allSatisfy { !$0.games.isEmpty }, "No empty category groups expected")
        // Check that localizedName is non-empty and not raw value
        for g in groups { #expect(!g.localizedName.isEmpty, "Localized category name should not be empty") }
        // Basic spot check a known category name mapping (English)
        if let exampleGroup = groups.first(where: { $0.category == .exampleGame }) {
            #expect(exampleGroup.localizedName == "Example Games")
        }
    }

    @Test func endgameMovesAreLoadedFromPGN() async throws {
        let loader = FamousGamesLoader.shared
        let all = loader.getAllGames()
        guard let endgameWithMoves = all.first(where: { $0.category == .endgame && $0.pgn != nil && !$0.pgn!.isEmpty }) else {
            #expect(Bool(false), "No endgame with PGN found")
            return
        }
        let vm = GameViewModel()
        vm.applyFamousGame(endgameWithMoves, broadcast: false)
        // After applying the game, move history should contain the moves from PGN
        #expect(vm.moveHistory.count > 0, "Endgame should have loaded moves from PGN, got \(vm.moveHistory.count) moves")
        #expect(vm.movesMade == vm.moveHistory.count, "movesMade should match moveHistory count")
    }

    // Validates that for every game: if a custom FEN is provided, the first PGN move is legal from that FEN;
    // otherwise it is legal from the standard initial position. This guards against future data regressions.
    @Test func pgnFirstMoveIsLegalFromDeclaredFEN() async throws {
        let games = FamousGamesLoader.shared.getAllGames()
        for game in games {
            guard let pgn = game.pgn, !pgn.isEmpty else { continue }
            // Extract first non-move-number SAN token from PGN
            let tokens = pgn.split(separator: " ")
            var firstToken: String? = nil
            tokenLoop: for raw in tokens {
                for part in PGNParser.splitCompoundMoveNumberToken(String(raw)) { // uses same utility
                    if part.isEmpty { continue }
                    if part.contains(".") { continue } // move number
                    if ["1-0","0-1","1/2-1/2","*"].contains(part) { continue }
                    firstToken = part
                    break tokenLoop
                }
            }
            guard let token = firstToken else { continue }
            var engine: ChessEngine
            if let fen = game.initialFEN, let custom = ChessEngine.fromFEN(fen) { engine = custom } else { engine = ChessEngine() }
            var parsingEngine = engine
            switch PGNParser.parseMoves(pgn: token, startingFrom: &parsingEngine) {
            case .success(let moves):
                #expect(!moves.isEmpty, "First PGN move for game \(game.title) failed to produce a move")
            case .failure:
                #expect(Bool(false), "First PGN move \(token) illegal from provided FEN in game \(game.title)")
            }
        }
    }

    // MARK: - Captured Pieces Baseline/FEN Tests


    @Test func capturedListsRemainEmptyInKQvKScenario() async throws {
        let fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1" // KQ vs K
        let vm = GameViewModel()
      let game = FamousGame(title: "KQvK Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
        vm.applyFamousGame(game, broadcast: false)
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty, "Captured lists should be empty initially for KQvK FEN")
    }

    @Test func noPhantomCapturesAfterNonCaptureMoveInKQvK() async throws {
        let fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1"
        let vm = GameViewModel()
        let game = FamousGame(title: "KQvK Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
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
        let game = FamousGame(title: "KQvK Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
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

    @Test func noPhantomHistoryCapturesInKQvKAfterQuietMoves() async throws {
        // Start from KQ vs K FEN (no pawns should appear)
        let fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1"
        let vm = GameViewModel()
        let game = FamousGame(title: "KQvK Quiet Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
        vm.applyFamousGame(game, broadcast: false)
        #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty)
        // Make two quiet moves (queen then king) ensuring no captures occur
        let qFrom = Square(file: 3, rank: 1) // d2
        let qTo = Square(file: 4, rank: 1)   // e2
        _ = vm.makeLocalMove(from: qFrom, to: qTo)
    // Black to move now; perform a quiet black king move e8 -> d8 (legal and not into check)
    let bkFrom = Square(file: 4, rank: 7) // e8
    let bkTo = Square(file: 3, rank: 7)   // d8
    let blackMoveOk = vm.makeLocalMove(from: bkFrom, to: bkTo)
    #expect(blackMoveOk, "Expected black king move e8->d8 to be legal")
        #expect(vm.moveHistory.count == 2)
        // Navigate history and ensure reconstruction shows no captures
        let recon0 = vm.captureReconstruction(at: 0)
        #expect(recon0.whiteCaptures.isEmpty && recon0.blackCaptures.isEmpty && recon0.lastCapturePieceID == nil)
        let recon1 = vm.captureReconstruction(at: 1)
        #expect(recon1.whiteCaptures.isEmpty && recon1.blackCaptures.isEmpty && recon1.lastCapturePieceID == nil)
        let recon2 = vm.captureReconstruction(at: 2)
        #expect(recon2.whiteCaptures.isEmpty && recon2.blackCaptures.isEmpty && recon2.lastCapturePieceID == nil)
        // historicalCaptureHighlight should be nil for indices 1 and 2 because no captures occurred
        #expect(vm.historicalCaptureHighlight(at: 1) == nil)
        #expect(vm.historicalCaptureHighlight(at: 2) == nil)
    }

    @Test func persistedQuietEndgameHasNoPhantomCaptures() async throws {
        // Use KQ vs K FEN with white to move; make quiet moves; save & reload; ensure no captures appear historically.
        let fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1"
        // Session 1
        do {
            let vm = GameViewModel()
            let game = FamousGame(title: "KQvK Persist Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
            vm.applyFamousGame(game, broadcast: false)
            #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty)
            // Two quiet queen moves: d2->e2, e2->f2
            let q1From = Square(file: 3, rank: 1)
            let q1To = Square(file: 4, rank: 1)
            _ = vm.makeLocalMove(from: q1From, to: q1To)
            let bkFrom = Square(file: 4, rank: 7) // e8
            let bkTo = Square(file: 3, rank: 7)   // d8
            let blackMoveOk = vm.makeLocalMove(from: bkFrom, to: bkTo)
            #expect(blackMoveOk, "Expected black king move e8->d8 to be legal")
            #expect(vm.moveHistory.count == 2)
            #expect(vm.capturedByMe.isEmpty && vm.capturedByOpponent.isEmpty)
            // Force save (already called internally on move, but explicit for clarity)
            vm.saveGame()
            // Reconstruction pre-persist
            for i in 0...2 {
                let recon = vm.captureReconstruction(at: i)
                #expect(recon.whiteCaptures.isEmpty && recon.blackCaptures.isEmpty && recon.lastCapturePieceID == nil, "Pre-persist recon at index \(i) should have no captures")
            }
        }
        // Session 2 (fresh instance reads persisted game)
        do {
            let vm2 = GameViewModel()
            vm2.loadGameIfAvailable()
            #expect(vm2.moveHistory.count == 2, "Reloaded history should have 2 moves")
            #expect(vm2.capturedByMe.isEmpty && vm2.capturedByOpponent.isEmpty, "Reloaded capture lists should be empty")
            for i in 0...2 {
                let recon = vm2.captureReconstruction(at: i)
                #expect(recon.whiteCaptures.isEmpty && recon.blackCaptures.isEmpty && recon.lastCapturePieceID == nil, "Post-load recon at index \(i) should have no captures")
            }
            // Scrub using historyIndex semantics (0,1,nil)
            vm2.historyIndex = 0
            let r0 = vm2.captureReconstruction(at: 0)
            #expect(r0.whiteCaptures.isEmpty && r0.blackCaptures.isEmpty)
            vm2.historyIndex = 1
            let r1 = vm2.captureReconstruction(at: 1)
            #expect(r1.whiteCaptures.isEmpty && r1.blackCaptures.isEmpty)
            vm2.historyIndex = nil
            let rLive = vm2.captureReconstruction(at: vm2.moveHistory.count)
            #expect(rLive.whiteCaptures.isEmpty && rLive.blackCaptures.isEmpty)
        }
    }
}
