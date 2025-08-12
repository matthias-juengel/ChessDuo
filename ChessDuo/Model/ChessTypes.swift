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
        case statusUpdate      // Peer status changes
        case joinRequest       // Request to join a host
        case joinResponse      // Host response with pairing code
        case pairingCode       // Code verification
        case gameSetup         // Game configuration
        case gameStart         // Finalized game start
        case rematchRequest    // Request for rematch
        case rematchResponse   // Response to rematch
    }
    
    let kind: Kind
    var move: Move? = nil
    var color: PieceColor? = nil
    var deviceName: String? = nil
    
    // New fields for enhanced networking
    var deviceId: String? = nil
    var peerStatus: PeerStatus? = nil
    var pairingCode: String? = nil
    var gameSetup: GameSetup? = nil
    var timestamp: Date? = nil
    var accepted: Bool? = nil
    var hostCandidate: HostCandidate? = nil
    
    init(kind: Kind, move: Move? = nil, color: PieceColor? = nil, deviceName: String? = nil) {
        self.kind = kind
        self.move = move
        self.color = color
        self.deviceName = deviceName
        self.timestamp = Date()
    }
}
