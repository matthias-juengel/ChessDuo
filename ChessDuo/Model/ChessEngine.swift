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
    
    // Castling rights tracking
    private var whiteCanCastleKingside = true
    private var whiteCanCastleQueenside = true
    private var blackCanCastleKingside = true
    private var blackCanCastleQueenside = true
    // En-passant target square (square that can be captured onto this ply)
    private var enPassantTarget: Square? = nil
    // Position repetition tracking (key -> count)
    private var positionCounts: [String:Int] = [:]

    init() {
        // Ensure initial position recorded
        recordInitialPosition()
    }

    mutating func reset() {
        board = .initial()
        sideToMove = .white
        whiteCanCastleKingside = true
        whiteCanCastleQueenside = true
        blackCanCastleKingside = true
        blackCanCastleQueenside = true
    enPassantTarget = nil
    positionCounts = [:]
    recordInitialPosition()
    }

    // Apply snapshot received from network (castling rights are conservatively reset)
    mutating func applySnapshot(board: Board, sideToMove: PieceColor) {
        self.board = board
        self.sideToMove = sideToMove
        // We don't transmit castling rights yet; recalculate basic rights heuristically.
        // Simple approach: if kings/rooks still on starting squares, keep rights else remove.
        whiteCanCastleKingside = canStillCastle(color: .white, kingside: true)
        whiteCanCastleQueenside = canStillCastle(color: .white, kingside: false)
        blackCanCastleKingside = canStillCastle(color: .black, kingside: true)
        blackCanCastleQueenside = canStillCastle(color: .black, kingside: false)
    enPassantTarget = nil
    positionCounts = [:]
    recordPosition()
    }

    static func fromSnapshot(board: Board, sideToMove: PieceColor) -> ChessEngine {
        var e = ChessEngine()
        e.applySnapshot(board: board, sideToMove: sideToMove)
        return e
    }

    private func canStillCastle(color: PieceColor, kingside: Bool) -> Bool {
        let rank = (color == .white) ? 0 : 7
        // King must be on starting square
        guard board.piece(at: Square(file: 4, rank: rank))?.type == .king,
              board.piece(at: Square(file: 4, rank: rank))?.color == color else { return false }
        let rookFile = kingside ? 7 : 0
        guard board.piece(at: Square(file: rookFile, rank: rank))?.type == .rook,
              board.piece(at: Square(file: rookFile, rank: rank))?.color == color else { return false }
        return true
    }

    // Sehr einfache Legalitätsprüfung (keine Schachprüfung, keine Rochade/en passant)
    mutating func tryMakeMove(_ m: Move) -> Bool {
        guard Board.inBounds(m.from), Board.inBounds(m.to) else { return false }
        guard var piece = board.piece(at: m.from) else { return false }
        guard piece.color == sideToMove else { return false }
        if !isPseudoLegal(piece: piece, from: m.from, to: m.to) { return false }
        
        // Check if this is a castling move
        let isCastling = piece.type == .king && abs(m.to.file - m.from.file) == 2
        
        if isCastling {
            // Special validation for castling
            if !isValidCastling(from: m.from, to: m.to, color: piece.color) { return false }
        } else {
            // Zielbelegung prüfen (nicht eigene Figur schlagen)
            if let dest = board.piece(at: m.to), dest.color == piece.color { return false }

            // Pfad frei für Sliding Pieces
            if [.rook, .bishop, .queen].contains(piece.type) {
                if !isPathClear(m.from, m.to, on: board) { return false }
            }
        }

        // Simulation auf Kopie durchführen
        var sim = board
        var simCastlingRights = (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside)
        applyCastlingMove(m, promotingFrom: &piece, on: &sim, castlingRights: &simCastlingRights)
        
        // Wenn eigener König im Schach bleibt/kommt, ist der Zug illegal
        if isKingInCheck(piece.color, on: sim) { return false }

        // Zug als gültig ausführen
        board = sim
        updateCastlingRights(move: m, piece: piece)
        // En-passant target setzen (nur direkt nach Doppelzug eines Bauern)
        if piece.type == .pawn && abs(m.to.rank - m.from.rank) == 2 {
            let passedRank = (m.to.rank + m.from.rank) / 2
            enPassantTarget = Square(file: m.from.file, rank: passedRank)
        } else {
            enPassantTarget = nil
        }
        sideToMove = sideToMove.opposite
    recordPosition()
        return true
    }
    
    private func isValidCastling(from: Square, to: Square, color: PieceColor) -> Bool {
        // King must not be in check currently
        if isKingInCheck(color, on: board) { return false }
        
        // Check that the king doesn't pass through or land on a square attacked by opponent
        let isKingside = to.file == 6
        let squaresToCheck = isKingside ? [5, 6] : [2, 3]
        
        for file in squaresToCheck {
            let square = Square(file: file, rank: from.rank)
            if isSquareAttacked(square, by: color.opposite, on: board) { return false }
        }
        
        return true
    }
    
    private mutating func updateCastlingRights(move: Move, piece: Piece) {
        // If king moves, lose all castling rights for that color
        if piece.type == .king {
            if piece.color == .white {
                whiteCanCastleKingside = false
                whiteCanCastleQueenside = false
            } else {
                blackCanCastleKingside = false
                blackCanCastleQueenside = false
            }
        }
        
        // If rook moves from its starting position, lose castling rights for that side
        if piece.type == .rook {
            if piece.color == .white && move.from.rank == 0 {
                if move.from.file == 0 { whiteCanCastleQueenside = false }
                if move.from.file == 7 { whiteCanCastleKingside = false }
            } else if piece.color == .black && move.from.rank == 7 {
                if move.from.file == 0 { blackCanCastleQueenside = false }
                if move.from.file == 7 { blackCanCastleKingside = false }
            }
        }
        
        // If a rook is captured, lose castling rights for that side
        if let capturedPiece = board.piece(at: move.to), capturedPiece.type == .rook {
            if capturedPiece.color == .white && move.to.rank == 0 {
                if move.to.file == 0 { whiteCanCastleQueenside = false }
                if move.to.file == 7 { whiteCanCastleKingside = false }
            } else if capturedPiece.color == .black && move.to.rank == 7 {
                if move.to.file == 0 { blackCanCastleQueenside = false }
                if move.to.file == 7 { blackCanCastleKingside = false }
            }
        }
    }

    // MARK: - Game state helpers (Checkmate)
    func isCheckmate(for color: PieceColor) -> Bool {
        // Checkmate: side is in check and has no legal move
        return isKingInCheck(color, on: board) && !hasAnyLegalMove(for: color)
    }

    /// Stalemate (Patt): side is NOT in check and has no legal move.
    func isStalemate(for color: PieceColor) -> Bool {
        return !isKingInCheck(color, on: board) && !hasAnyLegalMove(for: color)
    }

    /// Threefold repetition draw condition (current position occurred at least 3 times)
    func isThreefoldRepetition() -> Bool {
        let key = positionKey()
        return (positionCounts[key] ?? 0) >= 3
    }

    func hasAnyLegalMove(for color: PieceColor) -> Bool {
        // Try every piece and destination; early exit if a legal move exists
        for rank in 0..<8 {
            for file in 0..<8 {
                let from = Square(file: file, rank: rank)
                guard let piece = board.piece(at: from), piece.color == color else { continue }
                for tr in 0..<8 {
                    for tf in 0..<8 {
                        let to = Square(file: tf, rank: tr)
                        let m = Move(from: from, to: to)
                        // Mirror logic from tryMakeMove, but without mutating state
                        if !Board.inBounds(m.from) || !Board.inBounds(m.to) { continue }
                        if !isPseudoLegal(piece: piece, from: m.from, to: m.to) { continue }
                        
                        // Check if this is a castling move
                        let isCastling = piece.type == .king && abs(m.to.file - m.from.file) == 2
                        
                        if isCastling {
                            // Special validation for castling
                            if !isValidCastling(from: m.from, to: m.to, color: piece.color) { continue }
                        } else {
                            if let dest = board.piece(at: m.to), dest.color == piece.color { continue }
                            if [.rook, .bishop, .queen].contains(piece.type) {
                                if !isPathClear(m.from, m.to, on: board) { continue }
                            }
                        }
                        
                        var sim = board
                        var p = piece
                        var simCastlingRights = (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside)
                        applyCastlingMove(m, promotingFrom: &p, on: &sim, castlingRights: &simCastlingRights)
                        if !isKingInCheck(color, on: sim) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func isPseudoLegal(piece: Piece, from: Square, to: Square) -> Bool {
        let df = to.file - from.file
        let dr = to.rank - from.rank
        let adf = abs(df), adr = abs(dr)

        switch piece.type {
        case .king:
            // Normal king moves (one square in any direction)
            if max(adf, adr) == 1 { return true }
            
            // Castling moves (king moves two squares horizontally)
            if dr == 0 && adf == 2 {
                return isCastlingPseudoLegal(piece: piece, from: from, to: to)
            }
            return false
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
                // Diagonal schlagen (inkl. en passant)
                if let target = board.piece(at: to), target.color != piece.color { return true }
                // En passant: Zielfeld leer, aber entspricht enPassantTarget und hinter dem Ziel steht gegnerischer Bauer
                if board.piece(at: to) == nil, let ep = enPassantTarget, ep.file == to.file && ep.rank == to.rank {
                    let capturedPawnSquare = Square(file: to.file, rank: to.rank - dir)
                    if let captured = board.piece(at: capturedPawnSquare), captured.color != piece.color, captured.type == .pawn { return true }
                }
                return false
            } else {
                return false
            }
        }
    }
    
    private func isCastlingPseudoLegal(piece: Piece, from: Square, to: Square) -> Bool {
        // Only kings can castle
        guard piece.type == .king else { return false }
        
        let color = piece.color
        let expectedKingRank = (color == .white) ? 0 : 7
        
        // King must be on its starting square
        guard from.rank == expectedKingRank && from.file == 4 else { return false }
        
        // Determine if this is kingside or queenside castling
        let isKingside = to.file == 6
        let isQueenside = to.file == 2
        
        guard isKingside || isQueenside else { return false }
        guard to.rank == expectedKingRank else { return false }
        
        // Check if castling rights are still available
        if color == .white {
            if isKingside && !whiteCanCastleKingside { return false }
            if isQueenside && !whiteCanCastleQueenside { return false }
        } else {
            if isKingside && !blackCanCastleKingside { return false }
            if isQueenside && !blackCanCastleQueenside { return false }
        }
        
        // Check if the rook is in the correct position
        let rookFile = isKingside ? 7 : 0
        let rookSquare = Square(file: rookFile, rank: expectedKingRank)
        guard let rook = board.piece(at: rookSquare),
              rook.type == .rook,
              rook.color == color else { return false }
        
        // Check if squares between king and rook are empty
        let startFile = min(from.file, rookFile)
        let endFile = max(from.file, rookFile)
        for file in (startFile + 1)..<endFile {
            let square = Square(file: file, rank: expectedKingRank)
            if board.piece(at: square) != nil { return false }
        }
        
        return true
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
    // Public wrapper to query if a color is currently in check on the live board
    func isInCheck(_ color: PieceColor) -> Bool { isKingInCheck(color, on: board) }

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

    // Apply a move on a given board copy (promotion uses provided piece type if any)
    private func applyMove(_ m: Move, promotingFrom pieceRef: inout Piece, on b: inout Board) {
        b.set(nil, at: m.from)
        var piece = pieceRef
        // En passant capture removal: pawn moves diagonally to empty square that equals enPassantTarget
        if piece.type == .pawn && abs(m.to.file - m.from.file) == 1 && b.piece(at: m.to) == nil {
            let dir = (piece.color == .white) ? 1 : -1
            let capturedPawnSquare = Square(file: m.to.file, rank: m.to.rank - dir)
            if let cap = b.piece(at: capturedPawnSquare), cap.type == .pawn && cap.color != piece.color {
                b.set(nil, at: capturedPawnSquare)
            }
        }
        if piece.type == .pawn && ((m.to.rank == 7 && piece.color == .white) || (m.to.rank == 0 && piece.color == .black)) {
            let promoteTo = m.promotion ?? .queen
            piece = Piece(type: promoteTo, color: piece.color)
        }
        b.set(piece, at: m.to)
        pieceRef = piece
    }
    
    // Apply a move that could be castling or regular move
    private func applyCastlingMove(_ m: Move, promotingFrom pieceRef: inout Piece, on b: inout Board, castlingRights: inout (Bool, Bool, Bool, Bool)) {
        let piece = pieceRef
        
        // Check if this is a castling move
        if piece.type == .king && abs(m.to.file - m.from.file) == 2 {
            // This is castling - move both king and rook
            let isKingside = m.to.file == 6
            let rookFromFile = isKingside ? 7 : 0
            let rookToFile = isKingside ? 5 : 3
            let rank = m.from.rank
            
            // Move the king
            b.set(nil, at: m.from)
            b.set(piece, at: m.to)
            
            // Move the rook
            let rookFrom = Square(file: rookFromFile, rank: rank)
            let rookTo = Square(file: rookToFile, rank: rank)
            if let rook = b.piece(at: rookFrom) {
                b.set(nil, at: rookFrom)
                b.set(rook, at: rookTo)
            }
        } else {
            // Regular move
            applyMove(m, promotingFrom: &pieceRef, on: &b)
        }
    }

    // MARK: - Repetition helpers
    private mutating func recordInitialPosition() {
        positionCounts = [:]
        recordPosition()
    }
    private mutating func recordPosition() {
        let key = positionKey()
        positionCounts[key, default: 0] += 1
    }
    private func positionKey() -> String {
        // Encodes board layout, side to move, and castling rights (en-passant not implemented in engine)
        var s = String()
        for rank in 0..<8 {
            for file in 0..<8 {
                let sq = Square(file: file, rank: rank)
                if let p = board.piece(at: sq) {
                    let c = p.color == .white ? "w" : "b"
                    let t: String
                    switch p.type {
                    case .king: t = "k"
                    case .queen: t = "q"
                    case .rook: t = "r"
                    case .bishop: t = "b"
                    case .knight: t = "n"
                    case .pawn: t = "p"
                    }
                    s.append(c + t)
                } else {
                    s.append("__")
                }
            }
        }
        s.append("|")
        s.append(sideToMove == .white ? "w" : "b")
        s.append("|")
        let cr = [whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside]
    for flag in cr { s.append(flag ? "1" : "0") }
    s.append("|")
    if let ep = enPassantTarget { s.append("ep\(ep.file)\(ep.rank)") } else { s.append("-") }
        return s
    }
}
