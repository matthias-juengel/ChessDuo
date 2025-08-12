import Foundation

enum PieceColor: String, Codable { case white, black
    var opposite: PieceColor { self == .white ? .black : .white }
}

enum PieceType: String, Codable { case king, queen, rook, bishop, knight, pawn }

struct Piece: Codable, Equatable {
    let type: PieceType
    let color: PieceColor
}

struct Square: Hashable, Codable {
    let file: Int  // 0..7 (a..h)
    let rank: Int  // 0..7 (1..8, 0 ist „1“ unten für Weiß)
}

struct Move: Codable {
    let from: Square
    let to: Square
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
}
