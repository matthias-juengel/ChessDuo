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
            if !isPathClear(from: m.from, to: m.to) { return false }
        }

        // Zug ausführen
        board.set(nil, at: m.from)
        // Pawn Promotion automatisch zur Dame
        if piece.type == .pawn && (m.to.rank == 7 && piece.color == .white || m.to.rank == 0 && piece.color == .black) {
            piece = Piece(type: .queen, color: piece.color)
        }
        board.set(piece, at: m.to)

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
}
