//
//  ChessEngine.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import Foundation

struct ChessEngine: Codable {
    private(set) var board: Board = .initial()
    private(set) var sideToMove: PieceColor = .white

    mutating func reset() {
        board = .initial()
        sideToMove = .white
    }

    // Sehr einfache Legalitätsprüfung (keine Schachprüfung, keine Rochade/en passant)
    mutating func tryMakeMove(_ m: Move) -> Bool {
        guard Board.inBounds(m.from), Board.inBounds(m.to) else { return false }
        guard var piece = board.piece(at: m.from) else { return false }
        guard piece.color == sideToMove else { return false }
        if !isPseudoLegal(piece: piece, from: m.from, to: m.to) { return false }
        // Zielbelegung prüfen (nicht eigene Figur schlagen)
        if let dest = board.piece(at: m.to), dest.color == piece.color { return false }

        // Pfad frei für Sliding Pieces
        if [.rook, .bishop, .queen].contains(piece.type) {
            if !isPathClear(m.from, m.to, on: board) { return false }
        }

        // Simulation auf Kopie durchführen
        var sim = board
        applyMove(m, promotingFrom: &piece, on: &sim)
        // Wenn eigener König im Schach bleibt/kommt, ist der Zug illegal
        if isKingInCheck(piece.color, on: sim) { return false }

        // Zug als gültig ausführen
        board = sim
        sideToMove = sideToMove.opposite
        return true
    }

    private func isPseudoLegal(piece: Piece, from: Square, to: Square) -> Bool {
        let df = to.file - from.file
        let dr = to.rank - from.rank
        let adf = abs(df), adr = abs(dr)

        switch piece.type {
        case .king:
            return max(adf, adr) == 1
        case .queen:
            return df == 0 || dr == 0 || adf == adr
        case .rook:
            return df == 0 || dr == 0
        case .bishop:
            return adf == adr
        case .knight:
            return (adf == 1 && adr == 2) || (adf == 2 && adr == 1)
        case .pawn:
            let dir = (piece.color == .white) ? 1 : -1
            // Vorwärts
            if df == 0 {
                // ein Feld
                if dr == dir, board.piece(at: to) == nil { return true }
                // zwei Felder aus Grundreihe
                let startRank = (piece.color == .white) ? 1 : 6
                if from.rank == startRank, dr == 2*dir {
                    let mid = Square(file: from.file, rank: from.rank + dir)
                    return board.piece(at: mid) == nil && board.piece(at: to) == nil
                }
                return false
            } else if adf == 1, dr == dir {
                // Diagonal schlagen
                if let target = board.piece(at: to), target.color != piece.color { return true }
                return false
            } else {
                return false
            }
        }
    }

    private func isPathClear(from: Square, to: Square) -> Bool {
        var f = from.file, r = from.rank
        let stepF = (to.file - f).signum()
        let stepR = (to.rank - r).signum()
        // gehe bis vor Ziel
        repeat {
            f += stepF
            r += stepR
            if f == to.file && r == to.rank { break }
            if board.piece(at: .init(file: f, rank: r)) != nil { return false }
        } while true
        return true
    }

    // MARK: - Check / Attack detection
    private func isKingInCheck(_ color: PieceColor, on b: Board) -> Bool {
        guard let kSq = kingSquare(of: color, on: b) else { return false }
        return isSquareAttacked(kSq, by: color.opposite, on: b)
    }

    private func kingSquare(of color: PieceColor, on b: Board) -> Square? {
        for rank in 0..<8 {
            for file in 0..<8 {
                let sq = Square(file: file, rank: rank)
                if let p = b.piece(at: sq), p.type == .king, p.color == color {
                    return sq
                }
            }
        }
        return nil
    }

    private func isSquareAttacked(_ sq: Square, by attacker: PieceColor, on b: Board) -> Bool {
        // Knights
        let knightDeltas = [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)]
        for (df, dr) in knightDeltas {
            let t = Square(file: sq.file + df, rank: sq.rank + dr)
            if Board.inBounds(t), let p = b.piece(at: t), p.color == attacker, p.type == .knight { return true }
        }
        // King (adjacent squares)
        for df in -1...1 {
            for dr in -1...1 {
                if df == 0 && dr == 0 { continue }
                let t = Square(file: sq.file + df, rank: sq.rank + dr)
                if Board.inBounds(t), let p = b.piece(at: t), p.color == attacker, p.type == .king { return true }
            }
        }
        // Pawns (attack only diagonally forward)
        let dir = (attacker == .white) ? 1 : -1
        let pawnTargets = [Square(file: sq.file - 1, rank: sq.rank - dir), Square(file: sq.file + 1, rank: sq.rank - dir)]
        for t in pawnTargets where Board.inBounds(t) {
            if let p = b.piece(at: t), p.color == attacker, p.type == .pawn { return true }
        }
        // Sliding pieces: bishops/rooks/queens
        // Diagonals (bishop/queen)
        let diagSteps = [(1,1),(1,-1),(-1,1),(-1,-1)]
        for (sf, sr) in diagSteps {
            var f = sq.file + sf, r = sq.rank + sr
            while (0...7).contains(f) && (0...7).contains(r) {
                let t = Square(file: f, rank: r)
                if let piece = b.piece(at: t) {
                    if piece.color == attacker && (piece.type == .bishop || piece.type == .queen) { return true }
                    break
                }
                f += sf; r += sr
            }
        }
        // Ranks/files (rook/queen)
        let orthoSteps = [(1,0),(-1,0),(0,1),(0,-1)]
        for (sf, sr) in orthoSteps {
            var f = sq.file + sf, r = sq.rank + sr
            while (0...7).contains(f) && (0...7).contains(r) {
                let t = Square(file: f, rank: r)
                if let piece = b.piece(at: t) {
                    if piece.color == attacker && (piece.type == .rook || piece.type == .queen) { return true }
                    break
                }
                f += sf; r += sr
            }
        }
        return false
    }

    // Path-clear check on arbitrary board state
    private func isPathClear(_ from: Square, _ to: Square, on b: Board) -> Bool {
        var f = from.file, r = from.rank
        let stepF = (to.file - f).signum()
        let stepR = (to.rank - r).signum()
        repeat {
            f += stepF; r += stepR
            if f == to.file && r == to.rank { break }
            if b.piece(at: .init(file: f, rank: r)) != nil { return false }
        } while true
        return true
    }

    // Apply a move on a given board copy (with simple promotion to queen)
    private func applyMove(_ m: Move, promotingFrom pieceRef: inout Piece, on b: inout Board) {
        b.set(nil, at: m.from)
        var piece = pieceRef
        if piece.type == .pawn && ((m.to.rank == 7 && piece.color == .white) || (m.to.rank == 0 && piece.color == .black)) {
            piece = Piece(type: .queen, color: piece.color)
        }
        b.set(piece, at: m.to)
        pieceRef = piece
    }
}
