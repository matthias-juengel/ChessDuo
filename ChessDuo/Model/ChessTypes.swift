import Foundation

enum PieceColor: String, Codable { case white, black
    var opposite: PieceColor { self == .white ? .black : .white }
}

enum PieceType: String, Codable { case king, queen, rook, bishop, knight, pawn }

// Add stable identity so SwiftUI can animate moves (matchedGeometryEffect)
struct Piece: Codable, Equatable, Identifiable {
    let id: UUID
    let type: PieceType
    let color: PieceColor

    init(type: PieceType, color: PieceColor, id: UUID = UUID()) {
        self.id = id
        self.type = type
        self.color = color
    }

    // Custom CodingKeys to preserve backward compatibility possibility
    private enum CodingKeys: String, CodingKey { case id, type, color }
}

struct Square: Hashable, Codable {
    let file: Int  // 0..7 (a..h)
    let rank: Int  // 0..7 (1..8, 0 ist „1“ unten für Weiß)

    init(file: Int, rank: Int) { self.file = file; self.rank = rank }
    // Convenience algebraic initializer (e.g., "e4") for tests / debug tools
    init?(algebraic: String) {
        guard algebraic.count == 2,
              let fileChar = algebraic.lowercased().first,
              let rankChar = algebraic.last,
              let files = "abcdefgh".firstIndex(of: fileChar) else { return nil }
        let fileIndex = "abcdefgh".distance(from: "abcdefgh".startIndex, to: files)
        guard let rankVal = Int(String(rankChar)), (1...8).contains(rankVal) else { return nil }
        self.file = fileIndex
        self.rank = rankVal - 1
    }
}

struct Move: Codable {
    let from: Square
    let to: Square
    let promotion: PieceType?
    init(from: Square, to: Square, promotion: PieceType? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }
}

struct NetMessage: Codable {
    enum Kind: String, Codable {
        case move, reset, hello
        case proposeRole // sent by lexicographically smaller peer, proposes it will be white
        case acceptRole  // acknowledgement by other peer
    case requestReset // ask opponent to confirm reset
    case acceptReset  // opponent accepted reset
    case declineReset // opponent declined reset
        case syncRequest  // ask peer to send its current game snapshot
        case syncState    // contains full game snapshot
    case colorSwap    // pre-game swap of colors initiated by current white
    // History revert negotiation
    case requestHistoryRevert   // ask opponent to revert to a prior move count
    case acceptHistoryRevert    // opponent accepted revert (will follow with revertHistory)
    case declineHistoryRevert   // opponent declined revert
    case revertHistory          // authoritative revert to given move count
    case historyView            // peer is viewing a historical position (index provided or nil to exit)
    // Famous game load negotiation
    case requestLoadGame        // ask opponent to confirm loading a famous game (will end current game)
    case acceptLoadGame         // opponent accepted loading the game
    case declineLoadGame        // opponent declined loading the game
    case loadGameState          // authoritative load of a famous game snapshot
    }
    let kind: Kind
    var move: Move? = nil
    var color: PieceColor? = nil
    var deviceName: String? = nil // optional friendly device name
    // Snapshot fields (used for syncState)
    var board: Board? = nil
    var sideToMove: PieceColor? = nil // reuse field for clarity
    var movesMade: Int? = nil
    var capturedByMe: [Piece]? = nil // pieces captured by sender
    var capturedByOpponent: [Piece]? = nil // pieces captured by sender's opponent
    // Last move / capture highlight info (sender perspective)
    var lastMoveFrom: Square? = nil
    var lastMoveTo: Square? = nil
    var lastCapturedPieceID: UUID? = nil
    var lastCaptureByMe: Bool? = nil
    // Full move history (optional). Included for syncState to allow animation-ready reconstruction.
    var moveHistory: [Move]? = nil
    // History revert target (number of moves to keep) for revertHistory / requestHistoryRevert
    var revertToCount: Int? = nil
    // History view index (number of moves applied). nil represents live view.
    var historyViewIndex: Int? = nil
    // Famous game metadata (title) for load negotiation/reference
    var gameTitle: String? = nil
}
