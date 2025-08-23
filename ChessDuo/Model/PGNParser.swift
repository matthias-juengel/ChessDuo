import Foundation

/// Lightweight PGN (SAN) parser that converts a single main-line PGN string into a list of `Move` objects
/// understood by `ChessEngine`. It walks the moves sequentially, using the current legal move list at
/// each ply to resolve SAN tokens (including disambiguation and promotions). Variations are ignored.
/// Supported SAN features:
/// - Piece moves: Nf3, Qxe5, R1e2, Nbd7, Bxf7+
/// - Pawn moves: e4, exd5, dxe8=Q, c8=Q
/// - Castling: O-O, O-O-O (also 0-0 / 0-0-0 variants)
/// - Captures: 'x'
/// - Disambiguation by file, rank or both
/// - Promotions using =Q/R/B/N
/// - Check / mate suffixes '+', '#'
/// - Annotation glyphs ! ? !? ?! ignored
/// - Move numbers (e.g. 1. 23... ) ignored
/// - Result tokens (1-0, 0-1, 1/2-1/2, *) ignored
/// - Brace comments { ... } removed
/// - Semicolon comments (;) to end of line removed
/// - Parentheses for variations removed entirely (variation moves are skipped, only main line kept)
/// Limitations:
/// - Does not process NAGs ($1 etc) explicitly (they are stripped as unknown tokens)
/// - Does not validate check/mate indicator correctness
/// - If an unresolvable token appears, parsing stops and returns moves parsed so far as .failure
struct PGNParser {
    enum ParserError: Error, CustomStringConvertible {
        case invalidToken(String)
        case ambiguous(String)
        var description: String {
            switch self {
            case .invalidToken(let t): return "Invalid PGN token: \(t)"
            case .ambiguous(let t): return "Ambiguous PGN token could not be resolved uniquely: \(t)"
            }
        }
    }

    static func parseMoves(pgn: String) -> Result<[Move], ParserError> {
        var engine = ChessEngine()
        return parseMoves(pgn: pgn, startingFrom: &engine)
    }

    /// Parse moves starting from the given (already configured) engine state (e.g. custom FEN).
    /// The engine parameter is inout so that the caller can (optionally) observe the final evolved
    /// state after successful parsing. On failure the engine will reflect moves made up to the
    /// failing token (mirrors previous behaviour for ease of debugging).
    static func parseMoves(pgn: String, startingFrom engine: inout ChessEngine) -> Result<[Move], ParserError> {
        var cleaned = stripCommentsAndVariations(pgn)
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        while cleaned.contains("  ") { cleaned = cleaned.replacingOccurrences(of: "  ", with: " ") }
        let rawTokens = cleaned.split(separator: " ").map(String.init)
        var moves: [Move] = []
        for raw in rawTokens.flatMap(splitCompoundMoveNumberToken) {
            if raw.isEmpty { continue }
            let token = normalizeToken(raw)
            if token.isEmpty { continue }
            if isResultToken(token) { break }
            if isMoveNumber(token) { continue }
            if token == "O-O" || token == "0-0" { // kingside castle
                guard let move = castleMove(engine: engine, kingside: true) else { return .failure(.invalidToken(raw)) }
                _ = engine.tryMakeMove(move)
                moves.append(move)
                continue
            }
            if token == "O-O-O" || token == "0-0-0" { // queenside castle
                guard let move = castleMove(engine: engine, kingside: false) else { return .failure(.invalidToken(raw)) }
                _ = engine.tryMakeMove(move)
                moves.append(move)
                continue
            }
            if let move = resolveSAN(token: token, engine: engine) {
                _ = engine.tryMakeMove(move)
                moves.append(move)
            } else {
                return .failure(.invalidToken(raw))
            }
        }
        return .success(moves)
    }

    // MARK: - Core SAN resolution
    private static func resolveSAN(token original: String, engine: ChessEngine) -> Move? {
        var token = original
        // Strip trailing check/mate / annotations characters
        while let last = token.last, "+#?!".contains(last) { token.removeLast() }
        var promotion: PieceType? = nil
        if let eqRange = token.range(of: "=") {
            let nextIndex = token.index(after: eqRange.lowerBound)
            if nextIndex < token.endIndex {
                let promoChar = token[nextIndex]
                promotion = pieceType(fromPromotion: promoChar)
            }
            token.removeSubrange(eqRange.lowerBound..<token.endIndex) // remove =Q etc
        }
        // Capture indicator
        let isCapture = token.contains("x")
        token = token.replacingOccurrences(of: "x", with: "")

        // Identify piece type; default pawn if first char not KQRBN
        let pieceType: PieceType
        var rest = token
        if let first = token.first, "KQRBN".contains(first) {
            pieceType = mapPieceLetter(first)
            rest.removeFirst()
        } else {
            pieceType = .pawn
        }

        // Destination square are last two chars
        guard rest.count >= 2 else { return nil }
        let destFileChar = rest[rest.index(rest.endIndex, offsetBy: -2)]
        let destRankChar = rest.last!
        guard let destSq = square(fromFile: destFileChar, rankChar: destRankChar) else { return nil }
        let disambiguation = String(rest.dropLast(2)) // may be 0,1 or 2 chars

        // Collect legal candidate moves
        let legal = engine.generateLegalMoves(for: engine.sideToMove)
            .filter { move in
                if move.to != destSq { return false }
                // Check piece type
                guard let p = engine.board.piece(at: move.from), p.type == pieceType else { return false }
                // Promotion match
                if let promotion = promotion { if move.promotion != promotion { return false } }
                // Capture requirement: if SAN had 'x' ensure this move captures (including en passant)
                let isMoveCapture = isCaptureMove(move, engine: engine)
                if isCapture && !isMoveCapture { return false }
                if !isCapture && isMoveCapture && pieceType == .pawn && disambiguation.isEmpty { return false }
                // Disambiguation logic
                if !disambiguation.isEmpty {
                    let fileChars = "abcdefgh"
                    if disambiguation.count == 1 {
                        let c = disambiguation.first!
                        if fileChars.contains(c) { // file disambiguation
                            if fileChars[fileChars.index(fileChars.startIndex, offsetBy: move.from.file)] != c { return false }
                        } else if let r = Int(String(c)), r >= 1, r <= 8 {
                            if move.from.rank != (r - 1) { return false }
                        } else { return false }
                    } else if disambiguation.count == 2 {
                        // file + rank
                        let fChar = disambiguation.first!
                        let rChar = disambiguation.last!
                        guard fileChars.contains(fChar), let r = Int(String(rChar)), r >= 1, r <= 8 else { return false }
                        if fileChars[fileChars.index(fileChars.startIndex, offsetBy: move.from.file)] != fChar { return false }
                        if move.from.rank != (r - 1) { return false }
                    }
                }
                return true
            }
        if legal.isEmpty { return nil }
        if legal.count == 1 { return legal.first }
        // If ambiguity remains, fail (caller will treat as error)
        return nil
    }

    private static func isCaptureMove(_ move: Move, engine: ChessEngine) -> Bool {
        if let mover = engine.board.piece(at: move.from), mover.type == .pawn, move.from.file != move.to.file, engine.board.piece(at: move.to) == nil {
            // potential en passant; infer captured pawn square
            let dir = mover.color == .white ? 1 : -1
            let capturedSq = Square(file: move.to.file, rank: move.to.rank - dir)
            if let cap = engine.board.piece(at: capturedSq), cap.color != mover.color, cap.type == .pawn { return true }
        }
        if let dest = engine.board.piece(at: move.to) {
            if let mover = engine.board.piece(at: move.from), dest.color != mover.color { return true }
        }
        return false
    }

    // MARK: - Utilities
    private static func mapPieceLetter(_ c: Character) -> PieceType {
        switch c {
        case "K": return .king
        case "Q": return .queen
        case "R": return .rook
        case "B": return .bishop
        case "N": return .knight
        default: return .pawn
        }
    }
    private static func pieceType(fromPromotion c: Character) -> PieceType? {
        switch c { case "Q": return .queen; case "R": return .rook; case "B": return .bishop; case "N": return .knight; default: return nil }
    }
    private static func square(fromFile f: Character, rankChar r: Character) -> Square? {
        let files = "abcdefgh"
        guard let fileIndex = files.firstIndex(of: f) else { return nil }
        guard let rankVal = Int(String(r)), (1...8).contains(rankVal) else { return nil }
        return Square(file: files.distance(from: files.startIndex, to: fileIndex), rank: rankVal - 1)
    }
    private static func isMoveNumber(_ tok: String) -> Bool {
        let trimmed = tok.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return Int(trimmed) != nil && tok.contains(".")
    }
    private static func isResultToken(_ tok: String) -> Bool { ["1-0","0-1","1/2-1/2","*"] .contains(tok) }

    private static func normalizeToken(_ token: String) -> String {
        let t = token
        if t.first == "{" || t.first == ";" { return "" }
        if t.first == "$" { return "" } // ignore NAG
        return t
    }

    /// Split tokens that combine move number + SAN, e.g. "1.e4" -> ["1.", "e4"], "23...Qa5" -> ["23...", "Qa5"]
    // Internal for test visibility: splits tokens that combine move number + SAN, e.g. "12...Qa5".
    static func splitCompoundMoveNumberToken(_ token: String) -> [String] {
        // Find first period
        guard let dotIndex = token.firstIndex(of: ".") else { return [token] }
        let prefix = token[..<dotIndex]
        // Ensure prefix all digits
        if !prefix.allSatisfy({ $0.isNumber }) { return [token] }
        // Count consecutive dots
        var i = dotIndex
        var dots = 0
        while i < token.endIndex, token[i] == "." { dots += 1; i = token.index(after: i) }
        let moveNumberPart = String(prefix) + String(repeating: ".", count: dots)
        let remainder = String(token[i...])
        if remainder.isEmpty { return [moveNumberPart] }
        return [moveNumberPart, remainder]
    }

    private static func stripCommentsAndVariations(_ s: String) -> String {
        var result = s
        // Remove brace comments
        while let start = result.firstIndex(of: "{"), let end = result[start...].firstIndex(of: "}") {
            result.removeSubrange(start...end)
        }
        // Remove semicolon comments to end of line
        var lines: [String] = []
        for line in result.split(separator: "\n", omittingEmptySubsequences: false) {
            if let semi = line.firstIndex(of: ";") {
                lines.append(String(line[..<semi]))
            } else {
                lines.append(String(line))
            }
        }
        result = lines.joined(separator: "\n")
        // Remove parentheses and enclosed substrings entirely (drop variations)
        while let open = result.firstIndex(of: "("), let close = result[open...].firstIndex(of: ")") {
            result.removeSubrange(open...close)
        }
        return result
    }

    private static func castleMove(engine: ChessEngine, kingside: Bool) -> Move? {
        let legal = engine.generateLegalMoves(for: engine.sideToMove)
        let rank = engine.sideToMove == .white ? 0 : 7
        let kingFrom = Square(file: 4, rank: rank)
        let kingTo = Square(file: kingside ? 6 : 2, rank: rank)
        return legal.first { $0.from == kingFrom && $0.to == kingTo }
    }
}
