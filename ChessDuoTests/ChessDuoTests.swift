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

}
