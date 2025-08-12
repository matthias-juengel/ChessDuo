//
//  GameViewModel.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import Foundation
import Combine

final class GameViewModel: ObservableObject {
    @Published private(set) var engine = ChessEngine()
    @Published var myColor: PieceColor? = nil
    @Published var statusText: String = "Nicht verbunden"
    @Published var otherDeviceNames: [String] = []
    @Published var discoveredPeerNames: [String] = [] // for UI prompt
    @Published var capturedByMe: [Piece] = []
    @Published var capturedByOpponent: [Piece] = []
    @Published var movesMade: Int = 0
    @Published var awaitingResetConfirmation: Bool = false
    @Published var incomingResetRequest: Bool = false

    let peers = PeerService()
    private var cancellables: Set<AnyCancellable> = []
    private var hasSentHello = false

    init() {
        peers.onMessage = { [weak self] msg in
            self?.handle(msg)
        }
        peers.onPeerChange = { [weak self] in
            DispatchQueue.main.async { self?.attemptRoleProposalIfNeeded() }
        }

        // Mirror connected peer names into a published property for the UI
        peers.$connectedPeers
            .combineLatest(peers.$peerFriendlyNames)
            .map { peerIDs, friendlyMap in
                peerIDs.map { friendlyMap[$0.displayName] ?? $0.displayName }.sorted()
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] names in
                self?.otherDeviceNames = names
            }
            .store(in: &cancellables)

        // Observe connection changes to trigger automatic negotiation.
        peers.$connectedPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                guard let self = self else { return }
                if !peers.isEmpty {
                    if !self.hasSentHello { self.sendHello(); self.hasSentHello = true }
                    self.attemptRoleProposalIfNeeded()
                } else {
                    // Reset when all peers gone so a new connection can renegotiate.
                    self.myColor = nil
                    self.hasSentHello = false
                }
            }
            .store(in: &cancellables)

        // Mirror discovered peers to names for confirmation UI
        peers.$discoveredPeers
            .map { $0.map { $0.displayName }.sorted() }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] names in self?.discoveredPeerNames = names }
            .store(in: &cancellables)

    // Automatically start symmetric discovery
    peers.startAuto()
    }

    // User accepted to connect with a given peer name
    func confirmJoin(peerName: String) {
        if let target = peers.discoveredPeers.first(where: { $0.displayName == peerName }) {
            peers.invite(target)
        }
    }

    func host() {
        peers.startHosting()
        myColor = .white
        statusText = "Hosting… (Du bist Weiß)"
        sendHello()
    }

    func join() {
        peers.join()
        myColor = .black
        statusText = "Suche Host… (Du bist Schwarz)"
        sendHello()
    }

    func disconnect() {
        peers.stop()
        statusText = "Nicht verbunden"
    capturedByMe.removeAll()
    capturedByOpponent.removeAll()
    }

    private func sendHello() {
    peers.send(.init(kind: .hello, move: nil, color: myColor, deviceName: peers.localDisplayName))
    }

    func resetGame() {
        // Initiate reset handshake if moves happened; otherwise silent reset
        if movesMade == 0 {
            performLocalReset(send: true)
        } else {
            awaitingResetConfirmation = true
            peers.send(.init(kind: .requestReset))
        }
    }

    func makeMove(from: Square, to: Square) {
        guard let me = myColor, engine.sideToMove == me else { return }
        let move = Move(from: from, to: to)
        let capturedBefore = engine.board.piece(at: to)
        if engine.tryMakeMove(move) {
            peers.send(.init(kind: .move, move: move))
            if let cap = capturedBefore { capturedByMe.append(cap) }
            movesMade += 1
            updateStatusAfterMove()
        } else {
            statusText = "Illegaler Zug (König im Schach?)"
        }
    }

    private func handle(_ msg: NetMessage) {
        switch msg.kind {
        case .hello:
            // nichts weiter nötig; Anzeige aktualisieren
            statusText = peers.isConnected ? "Verbunden" : statusText
            attemptRoleProposalIfNeeded()
        case .reset:
            engine.reset()
            capturedByMe.removeAll()
            capturedByOpponent.removeAll()
            statusText = "Neu gestartet. Am Zug: Weiß"
            movesMade = 0
            awaitingResetConfirmation = false
            incomingResetRequest = false
        case .move:
            if let m = msg.move {
                let capturedBefore = engine.board.piece(at: m.to)
                if engine.tryMakeMove(m) {
                    if let cap = capturedBefore, cap.color == myColor { capturedByOpponent.append(cap) }
                }
                movesMade += 1
                updateStatusAfterMove()
            }
        case .proposeRole:
            // Other peer proposes it is white; accept if we don't have a color yet.
            if myColor == nil {
                myColor = .black
                statusText = "Verbunden – Du bist Schwarz"
                peers.send(.init(kind: .acceptRole))
            }
        case .acceptRole:
            // Other peer accepted our proposal, we should already have set our color.
            if myColor == nil { myColor = .white }
            statusText = "Verbunden – Du bist Weiß"
        case .requestReset:
            incomingResetRequest = true
        case .acceptReset:
            performLocalReset(send: true)
        case .declineReset:
            awaitingResetConfirmation = false
            incomingResetRequest = false
            statusText = "Gegner hat Reset abgelehnt"
        }
    }

    /// If colors not assigned yet and exactly one peer connected, decide deterministically.
    private func attemptRoleProposalIfNeeded() {
        guard myColor == nil, let first = peers.connectedPeers.first else { return }
        // Use lexicographical comparison of display names to pick white to ensure symmetry
        let iAmWhite = peers.localDisplayName < first.displayName
        if iAmWhite {
            myColor = .white
            statusText = "Verbunden – Du bist Weiß"
            peers.send(.init(kind: .proposeRole))
        } else {
            // Wait to receive proposeRole; if none arrives (race), we can still fallback later.
        }
    }

    private func performLocalReset(send: Bool) {
        engine.reset()
        capturedByMe.removeAll()
        capturedByOpponent.removeAll()
        movesMade = 0
        awaitingResetConfirmation = false
        incomingResetRequest = false
        statusText = "Neu gestartet. Am Zug: Weiß"
        if send { peers.send(.init(kind: .reset)) }
    }

    func respondToResetRequest(accept: Bool) {
        if accept {
            peers.send(.init(kind: .acceptReset))
            performLocalReset(send: true)
        } else {
            peers.send(.init(kind: .declineReset))
            incomingResetRequest = false
        }
    }

    private func updateStatusAfterMove() {
        // Prüfe auf Schachmatt für die Seite, die jetzt am Zug wäre
        let side = engine.sideToMove
        if engine.isCheckmate(for: side) {
            let winner = side.opposite
            statusText = "Schachmatt! \(winner == .white ? "Weiß" : "Schwarz") gewinnt."
        } else {
            statusText = "Am Zug: \(engine.sideToMove == .white ? "Weiß" : "Schwarz")"
        }
    }
}
