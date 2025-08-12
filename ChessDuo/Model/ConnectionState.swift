//
//  ConnectionState.swift
//  ChessDuo
//
//  Created for new UX implementation
//

import Foundation

// Connection states for the new UX flow
enum ConnectionState: String, Codable {
    case idle           // Initial state: scanning and advertising as available
    case proposedHost   // Soft host: no active host found within 1.5s
    case host          // Hard host: confirmed as the host
    case joiningLobby  // Looking at available hosts to join
    case pairing       // Exchanging pairing codes
    case gameSetup     // Choosing colors and game options
    case playing       // Game in progress
    case disconnected  // No connection
}

// Peer status for advertising
enum PeerStatus: String, Codable {
    case available     // Can join or become host
    case proposedHost  // Soft host proposal
    case host         // Active host
    case playing      // In a game
    case joinRequested // Sent join request, waiting for pairing
}

// Host election data for deterministic selection
struct HostCandidate: Codable, Hashable {
    let deviceId: String
    let displayName: String
    let rssi: Int?  // Signal strength (when available)
    let timestamp: Date
    
    // Deterministic comparison for host election
    static func < (lhs: HostCandidate, rhs: HostCandidate) -> Bool {
        // Primary: lexicographic device ID (deterministic)
        if lhs.deviceId != rhs.deviceId {
            return lhs.deviceId < rhs.deviceId
        }
        // Tie-breaker: stronger signal preferred
        if let lhsRssi = lhs.rssi, let rhsRssi = rhs.rssi {
            return lhsRssi > rhsRssi
        }
        // Fallback: earlier timestamp
        return lhs.timestamp < rhs.timestamp
    }
}

// Pairing code generation
struct PairingCode {
    static func generate() -> String {
        let code = Int.random(in: 1000...9999)
        return String(format: "%04d", code)
    }
    
    static func generateEmoji() -> String {
        let emojis = ["🐴", "⭐", "🎯", "🚀", "🎸", "🎨", "🎲", "🎭", "🎪", "🎺"]
        let first = emojis.randomElement()!
        let second = emojis.randomElement()!
        return "\(first)\(second)"
    }
}

// Game setup options
struct GameSetup: Codable {
    enum ColorChoice: String, Codable, CaseIterable {
        case random = "Zufällig"
        case iWantWhite = "Ich bin Weiß"
        case opponentWhite = "Gegner ist Weiß"
    }
    
    enum TimeControl: String, Codable, CaseIterable {
        case three = "3 min"
        case five = "5 min" 
        case ten = "10 min"
        case fifteen = "15 min"
        case unlimited = "Unbegrenzt"
        
        var minutes: Int? {
            switch self {
            case .three: return 3
            case .five: return 5
            case .ten: return 10
            case .fifteen: return 15
            case .unlimited: return nil
            }
        }
    }
    
    var colorChoice: ColorChoice = .random
    var timeControl: TimeControl = .ten
    
    // Resolve the actual colors based on the choice
    func resolveColors(hostRequested: Bool) -> (hostColor: PieceColor, joinerColor: PieceColor) {
        switch colorChoice {
        case .random:
            let hostIsWhite = Bool.random()
            return hostIsWhite ? (.white, .black) : (.black, .white)
        case .iWantWhite:
            return hostRequested ? (.white, .black) : (.black, .white)
        case .opponentWhite:
            return hostRequested ? (.black, .white) : (.white, .black)
        }
    }
}