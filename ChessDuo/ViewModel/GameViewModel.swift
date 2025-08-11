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
    @Published var capturedByMe: [Piece] = []
    @Published var capturedByOpponent: [Piece] = []

    let peers = PeerService()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        peers.onMessage = { [weak self] msg in
            self?.handle(msg)
        }

        // Mirror connected peer names into a published property for the UI
        peers.$connectedPeers
            .map { peers in peers.map { $0.displayName }.sorted() }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] names in
                self?.otherDeviceNames = names
            }
            .store(in: &cancellables)
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
        peers.send(.init(kind: .hello, move: nil, color: myColor))
    }

    func resetGame() {
        engine.reset()
    capturedByMe.removeAll()
    capturedByOpponent.removeAll()
        peers.send(.init(kind: .reset))
    }

    func makeMove(from: Square, to: Square) {
        guard let me = myColor, engine.sideToMove == me else { return }
        let move = Move(from: from, to: to)
        let capturedBefore = engine.board.piece(at: to)
        if engine.tryMakeMove(move) {
            peers.send(.init(kind: .move, move: move))
            if let cap = capturedBefore { capturedByMe.append(cap) }
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
        case .reset:
            engine.reset()
            statusText = "Neu gestartet. Am Zug: Weiß"
        case .move:
            if let m = msg.move {
                let capturedBefore = engine.board.piece(at: m.to)
                if engine.tryMakeMove(m) {
                    if let cap = capturedBefore, cap.color == myColor { capturedByOpponent.append(cap) }
                }
                updateStatusAfterMove()
            }
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
