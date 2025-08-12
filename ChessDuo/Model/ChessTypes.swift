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
    }
    let kind: Kind
    var move: Move? = nil
    var color: PieceColor? = nil
    var deviceName: String? = nil // optional friendly device name
}
