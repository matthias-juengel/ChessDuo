//
//  EnhancedGameViewModel.swift
//  ChessDuo
//
//  Enhanced GameViewModel for new UX implementation
//

import Foundation
import Combine

final class EnhancedGameViewModel: ObservableObject {
    @Published private(set) var engine = ChessEngine()
    @Published var myColor: PieceColor? = nil
    @Published var capturedByMe: [Piece] = []
    @Published var capturedByOpponent: [Piece] = []
    
    let peerService = EnhancedPeerService()
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        // Handle messages from peer service
        peerService.onMessage = { [weak self] msg in
            self?.handle(msg)
        }
        
        // Handle connection established
        peerService.onConnectionEstablished = { [weak self] in
            self?.handleConnectionEstablished()
        }
        
        // Handle connection lost
        peerService.onConnectionLost = { [weak self] in
            self?.handleConnectionLost()
        }
    }
    
    // MARK: - Game Actions
    
    func makeMove(from: Square, to: Square) {
        guard let me = myColor, engine.sideToMove == me else { return }
        let move = Move(from: from, to: to)
        let capturedBefore = engine.board.piece(at: to)
        
        if engine.tryMakeMove(move) {
            // Send move to peer
            let msg = NetMessage(kind: .move, move: move)
            peerService.sendMessage(msg)
            
            // Update captures
            if let cap = capturedBefore { capturedByMe.append(cap) }
        }
    }
    
    func resetGame() {
        engine.reset()
        capturedByMe.removeAll()
        capturedByOpponent.removeAll()
        
        let msg = NetMessage(kind: .reset)
        peerService.sendMessage(msg)
    }
    
    func requestRematch() {
        let msg = NetMessage(kind: .rematchRequest)
        peerService.sendMessage(msg)
    }
    
    func respondToRematch(accepted: Bool) {
        let msg = NetMessage(kind: .rematchResponse)
        msg.accepted = accepted
        peerService.sendMessage(msg)
        
        if accepted {
            // Switch colors for rematch
            myColor = myColor?.opposite
            resetGame()
        }
    }
    
    // MARK: - Connection Handling
    
    private func handleConnectionEstablished() {
        // Determine colors based on game setup
        let isHost = peerService.peerStatus == .host
        let colors = peerService.gameSetup.resolveColors(hostRequested: isHost)
        
        myColor = isHost ? colors.hostColor : colors.joinerColor
        
        // Send hello message with color info
        let msg = NetMessage(kind: .hello, color: myColor, deviceName: peerService.localDisplayName)
        peerService.sendMessage(msg)
    }
    
    private func handleConnectionLost() {
        // Handle disconnection during game
        // Could show reconnection dialog or return to lobby
    }
    
    // MARK: - Message Handling
    
    private func handle(_ msg: NetMessage) {
        switch msg.kind {
        case .hello:
            // Connection established, colors may be set
            break
            
        case .reset:
            engine.reset()
            capturedByMe.removeAll()
            capturedByOpponent.removeAll()
            
        case .move:
            if let move = msg.move {
                let capturedBefore = engine.board.piece(at: move.to)
                if engine.tryMakeMove(move) {
                    if let cap = capturedBefore, cap.color == myColor {
                        capturedByOpponent.append(cap)
                    }
                }
            }
            
        case .rematchRequest:
            // Show rematch dialog/notification
            // This would typically trigger a UI update
            break
            
        case .rematchResponse:
            if let accepted = msg.accepted, accepted {
                // Switch colors and reset
                myColor = myColor?.opposite
                resetGame()
            }
            
        default:
            // Other messages handled by PeerService
            break
        }
    }
    
    // MARK: - Computed Properties
    
    var isMyTurn: Bool {
        guard let myColor = myColor else { return false }
        return engine.sideToMove == myColor
    }
    
    var gameStatus: String {
        let currentSide = engine.sideToMove
        
        if engine.isCheckmate(for: currentSide) {
            let winner = currentSide.opposite
            return "Schachmatt! \(winner == .white ? "Weiß" : "Schwarz") gewinnt."
        } else if engine.isInCheck(for: currentSide) {
            return "Schach! \(currentSide == .white ? "Weiß" : "Schwarz") am Zug."
        } else {
            return "Am Zug: \(currentSide == .white ? "Weiß" : "Schwarz")"
        }
    }
    
    var connectionStatus: String {
        switch peerService.connectionState {
        case .idle:
            return "Suche nach Spielen..."
        case .proposedHost:
            return "Bereit als Host"
        case .host:
            return "Warte auf Spieler..."
        case .joiningLobby:
            return "Spiele gefunden"
        case .pairing:
            return "Verbinde..."
        case .gameSetup:
            return "Spiel wird eingerichtet..."
        case .playing:
            if let peerName = peerService.connectedPeer?.displayName {
                return "Verbunden mit \(peerName)"
            } else {
                return "Spiel läuft"
            }
        case .disconnected:
            return "Nicht verbunden"
        }
    }
}