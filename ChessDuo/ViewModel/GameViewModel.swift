//
//  GameViewModel.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import Foundation
import Combine
import SwiftUI

final class GameViewModel: ObservableObject {
    @Published private(set) var engine = ChessEngine()
    @Published var myColor: PieceColor? = nil
    @Published var statusText: String = "Nicht verbunden"
    @Published var otherDeviceNames: [String] = []
    @Published var discoveredPeerNames: [String] = [] // for UI prompt (friendly names without unique suffix)
    @Published var capturedByMe: [Piece] = []
    @Published var capturedByOpponent: [Piece] = []
    @Published var movesMade: Int = 0
    @Published var awaitingResetConfirmation: Bool = false
    @Published var incomingResetRequest: Bool = false
    @Published var outcome: GameOutcome = .ongoing
    @Published var incomingJoinRequestPeer: String? = nil
    @Published var offlineResetPrompt: Bool = false
    @Published var lastMove: Move? = nil
    @Published var lastCapturedPieceID: UUID? = nil
    @Published var lastCaptureByMe: Bool? = nil
    // Promotion handling
    @Published var pendingPromotionMove: Move? = nil // move without promotion yet
    @Published var showingPromotionPicker: Bool = false
    
    // Export current game state as a textual snapshot (for debugging / tests)
    func exportText() -> String {
    // Ensure status is up to date before exporting (fallback safety)
    recomputeOutcomeIfNeeded()
        var lines: [String] = []
        lines.append("ChessDuoExport v1")
        // Board in FEN-style ranks 8..1
        lines.append("Board:")
        for rank in (0..<8).reversed() { // 7 down to 0
            var fenRank = ""
            var emptyCount = 0
            for file in 0..<8 {
                let sq = Square(file: file, rank: rank)
                if let p = engine.board.piece(at: sq) {
                    if emptyCount > 0 { fenRank.append(String(emptyCount)); emptyCount = 0 }
                    fenRank.append(pieceChar(p))
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 { fenRank.append(String(emptyCount)) }
            lines.append(fenRank)
        }
        lines.append("SideToMove: \(engine.sideToMove == .white ? "w" : "b")")
        lines.append("MovesMade: \(movesMade)")
        if let lm = lastMove { lines.append("LastMove: \(algebraic(lm.from))->\(algebraic(lm.to))") }
        lines.append("Outcome: \(outcomeString(outcome))")
        // Captured pieces (approximate perspective neutral): compute missing from initial for each color
        lines.append("CapturedWhite: \(capturedPiecesDescription(color: .white))")
        lines.append("CapturedBlack: \(capturedPiecesDescription(color: .black))")
            let legal = engine.generateLegalMoves(for: engine.sideToMove)
                .map { "\(algebraic($0.from))->\(algebraic($0.to))" }
                .sorted()
            lines.append("LegalMoves: \(legal.joined(separator: ","))")
        let side = engine.sideToMove
        lines.append("InCheck: \(engine.isInCheck(side) ? "1" : "0")")
        lines.append("Checkmate: \(engine.isCheckmate(for: side) ? "1" : "0")")
        lines.append("Stalemate: \(engine.isStalemate(for: side) ? "1" : "0")")
        return lines.joined(separator: "\n")
    }

    private func pieceChar(_ p: Piece) -> String {
        let map: [PieceType:String] = [.king:"k", .queen:"q", .rook:"r", .bishop:"b", .knight:"n", .pawn:"p"]
        let base = map[p.type] ?? "?"
        return p.color == .white ? base.uppercased() : base
    }
    private func algebraic(_ sq: Square) -> String {
        let files = "abcdefgh"
        let fileChar = files[files.index(files.startIndex, offsetBy: sq.file)]
        return "\(fileChar)\(sq.rank + 1)"
    }
    private func outcomeString(_ o: GameOutcome) -> String {
        switch o { case .ongoing: return "ongoing"; case .win: return "win"; case .loss: return "loss"; case .draw: return "draw" }
    }
    private func capturedPiecesDescription(color: PieceColor) -> String {
        // Count initial pieces per color
        var initial: [PieceType:Int] = [.king:1, .queen:1, .rook:2, .bishop:2, .knight:2, .pawn:8]
        // Subtract those still on board
        for rank in 0..<8 { for file in 0..<8 { let sq = Square(file: file, rank: rank); if let p = engine.board.piece(at: sq), p.color == color { initial[p.type, default:0] -= 1 } } }
        // Build string
        return initial.compactMap { (type, missing) in missing > 0 ? "\(missing)x\(pieceChar(Piece(type: type, color: color)))" : nil }.sorted().joined(separator: ",")
    }

    func recomputeOutcomeIfNeeded() {
        let side = engine.sideToMove
        let currentOutcome = outcome
        let isMate = engine.isCheckmate(for: side)
        let isStale = engine.isStalemate(for: side)
        let isRep = engine.isThreefoldRepetition()
        if isMate {
            let winner = side.opposite
            if winner == myColor { outcome = .win; statusText = "Du hast gewonnen" } else if myColor != nil { outcome = .loss; statusText = "Du bist Matt" } else { statusText = "Schachmatt" }
        } else if isStale {
            outcome = .draw; statusText = "Remis"
        } else if isRep {
            outcome = .draw; statusText = "Remis (dreifache Stellungswiederholung)"
        } else if currentOutcome != .ongoing {
            // Keep terminal result
        } else {
            outcome = .ongoing
        }
    }

    let peers = PeerService()
    private var cancellables: Set<AnyCancellable> = []
    private var hasSentHello = false
    private var pendingInvitationDecision: ((Bool)->Void)? = nil
    enum GameOutcome: Equatable { case ongoing, win, loss, draw }

    init() {
        peers.onMessage = { [weak self] msg in
            self?.handle(msg)
        }
        peers.onPeerChange = { [weak self] in
            DispatchQueue.main.async { self?.attemptRoleProposalIfNeeded() }
        }
        peers.onInvitation = { [weak self] peerName, decision in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.incomingJoinRequestPeer = peerName
                self.pendingInvitationDecision = decision
            }
        }

        // Mirror connected peer names into a published property for the UI (strip suffix unless friendly map has real name)
        peers.$connectedPeers
            .combineLatest(peers.$peerFriendlyNames)
            .map { peerIDs, friendlyMap in
                peerIDs.map { peer in
                    if let friendly = friendlyMap[peer.displayName] { return friendly }
                    return Self.baseName(from: peer.displayName)
                }.sorted()
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
                    // Initiate state sync (both sides may request; reconciliation chooses higher move count)
                    self.requestSync()
                } else {
                    // Reset when all peers gone so a new connection can renegotiate.
                    self.myColor = nil
                    self.hasSentHello = false
                }
            }
            .store(in: &cancellables)

        // Mirror discovered peers to names for confirmation UI (strip suffix)
        peers.$discoveredPeers
            .map { $0.map { Self.baseName(from: $0.displayName) }.sorted() }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] names in self?.discoveredPeerNames = names }
            .store(in: &cancellables)

    // Automatically start symmetric discovery
    peers.startAuto()
    }

    // User accepted to connect with a given peer name
    func confirmJoin(peerName: String) {
        // Match by friendly base name (since UI lists stripped names); if multiple (same friendly name on different devices) pick lexicographically smallest full display name for determinism.
        let candidates = peers.discoveredPeers.filter { Self.baseName(from: $0.displayName) == peerName }
        if let target = candidates.sorted(by: { $0.displayName < $1.displayName }).first {
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
    awaitingResetConfirmation = false
    incomingResetRequest = false
    movesMade = 0
    }

    private func sendHello() {
        // Send the friendly (unsuffixed) device name
        peers.send(.init(kind: .hello, move: nil, color: myColor, deviceName: peers.localFriendlyName))
    }

    func resetGame() {
        if peers.isConnected {
            // Connected mode: handshake reset
            if movesMade == 0 {
                performLocalReset(send: true)
            } else {
                awaitingResetConfirmation = true
                incomingResetRequest = false // ensure only one alert
                peers.send(.init(kind: .requestReset))
            }
        } else {
            // Single-device mode: show alert confirmation (no network messages)
            if movesMade == 0 {
                performLocalReset(send: false)
            } else {
                offlineResetPrompt = true
            }
        }
    }

    func makeMove(from: Square, to: Square) {
        guard outcome == .ongoing else { return }
        guard let me = myColor, engine.sideToMove == me else { return }
        let isPromotion = isPromotionMove(from: from, to: to)
        if isPromotion {
            // Defer until user picks piece
            pendingPromotionMove = Move(from: from, to: to, promotion: nil)
            showingPromotionPicker = true
            return
        }
        let move = Move(from: from, to: to)
        let capturedBefore = engine.board.piece(at: to)
    if engine.tryMakeMove(move) {
        withAnimation(.easeInOut(duration: 0.35)) {
            peers.send(.init(kind: .move, move: move))
            if let cap = capturedBefore {
                capturedByMe.append(cap)
                lastCapturedPieceID = cap.id
                lastCaptureByMe = true
            } else {
                lastCapturedPieceID = nil
                lastCaptureByMe = nil
            }
            movesMade += 1
            lastMove = move
            updateStatusAfterMove()
            recomputeOutcomeIfNeeded()
        }
    } else {
        statusText = "Illegaler Zug (König im Schach?)"
    }
    }

    /// Local move for single-device mode (no network); both colors playable
    func makeLocalMove(from: Square, to: Square) {
        guard outcome == .ongoing else { return }
        let isPromotion = isPromotionMove(from: from, to: to)
        if isPromotion {
            pendingPromotionMove = Move(from: from, to: to, promotion: nil)
            showingPromotionPicker = true
            return
        }
        let move = Move(from: from, to: to)
        let moverColor = engine.sideToMove
        let capturedBefore = engine.board.piece(at: to)
    if engine.tryMakeMove(move) {
        withAnimation(.easeInOut(duration: 0.35)) {
            if let cap = capturedBefore {
                // Attribute capture list based on mover color (white = my side list if we treat white bottom)
                if moverColor == .white {
                    capturedByMe.append(cap)
                    lastCaptureByMe = true
                } else {
                    capturedByOpponent.append(cap)
                    lastCaptureByMe = false
                }
                lastCapturedPieceID = cap.id
            } else {
                lastCapturedPieceID = nil
                lastCaptureByMe = nil
            }
            movesMade += 1
            lastMove = move
            updateStatusAfterMove()
            recomputeOutcomeIfNeeded()
        }
    }
    }

    private func handle(_ msg: NetMessage) {
        switch msg.kind {
        case .hello:
            // nichts weiter nötig; Anzeige aktualisieren
            statusText = peers.isConnected ? "Verbunden" : statusText
            attemptRoleProposalIfNeeded()
            requestSync()
        case .reset:
            engine.reset()
            capturedByMe.removeAll()
            capturedByOpponent.removeAll()
            statusText = "Neu gestartet. Am Zug: Weiß"
            movesMade = 0
            awaitingResetConfirmation = false
            incomingResetRequest = false
            lastMove = nil
            lastCapturedPieceID = nil
            lastCaptureByMe = nil
        case .move:
            if let m = msg.move {
                let capturedBefore = engine.board.piece(at: m.to)
                if outcome == .ongoing, engine.tryMakeMove(m) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        if let cap = capturedBefore, cap.color == myColor {
                            capturedByOpponent.append(cap)
                            lastCapturedPieceID = cap.id
                            lastCaptureByMe = false
                        } else if let cap = capturedBefore {
                            lastCapturedPieceID = cap.id
                            lastCaptureByMe = true
                        } else {
                            lastCapturedPieceID = nil
                            lastCaptureByMe = nil
                        }
                        movesMade += 1
                        lastMove = m
                        updateStatusAfterMove()
                    }
                } else {
                    updateStatusAfterMove()
                }
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
            // Show incoming request; cancel any outgoing waiting state
            incomingResetRequest = true
            awaitingResetConfirmation = false
        case .acceptReset:
            performLocalReset(send: true)
        case .declineReset:
            awaitingResetConfirmation = false
            incomingResetRequest = false
            statusText = "Gegner hat Reset abgelehnt"
        case .syncRequest:
            sendSnapshot()
        case .syncState:
            // Compare movesMade and adopt if remote is ahead
            if let remoteMoves = msg.movesMade, remoteMoves > movesMade,
               let b = msg.board,
               let stm = msg.sideToMove,
               let remoteCapturedBySender = msg.capturedByMe,
               let remoteCapturedByOpponent = msg.capturedByOpponent {
                // Sender's capturedByMe -> our capturedByOpponent
                engine = ChessEngine.fromSnapshot(board: b, sideToMove: stm)
                capturedByOpponent = remoteCapturedBySender
                capturedByMe = remoteCapturedByOpponent
                movesMade = remoteMoves
                statusText = "Synchronisiert (Übernahme)"
                // Adopt last move / capture highlighting from remote (translate perspective)
                if let from = msg.lastMoveFrom, let to = msg.lastMoveTo {
                    lastMove = Move(from: from, to: to)
                } else {
                    lastMove = nil
                }
                // Capture highlight: if remote lastCaptureByMe == true, then from our POV the capture was by opponent.
                if let capID = msg.lastCapturedPieceID, let bySender = msg.lastCaptureByMe {
                    lastCapturedPieceID = capID
                    lastCaptureByMe = !bySender // invert perspective
                } else {
                    lastCapturedPieceID = nil
                    lastCaptureByMe = nil
                }
                recomputeOutcomeIfNeeded()
            } else if let remoteMoves = msg.movesMade, remoteMoves < movesMade {
                // We're ahead; send our snapshot back (echo) so peer can adopt.
                sendSnapshot()
            }
        case .colorSwap:
            // Swap colors locally if no moves made yet
            if movesMade == 0, let current = myColor { myColor = current.opposite }
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

    func performLocalReset(send: Bool) {
        engine.reset()
        capturedByMe.removeAll()
        capturedByOpponent.removeAll()
        movesMade = 0
        awaitingResetConfirmation = false
        incomingResetRequest = false
    offlineResetPrompt = false
        statusText = "Neu gestartet. Am Zug: Weiß"
        outcome = .ongoing
    lastMove = nil
    lastCapturedPieceID = nil
    lastCaptureByMe = nil
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

    func respondToIncomingInvitation(_ accept: Bool) {
        pendingInvitationDecision?(accept)
        pendingInvitationDecision = nil
        incomingJoinRequestPeer = nil
    }

    // Host (white) can swap colors before any move has been made.
    func swapColorsIfAllowed() {
        guard movesMade == 0, let me = myColor else { return }
        // Only allow the current white to initiate swap (to avoid race)
        guard me == .white else { return }
        myColor = .black
        peers.send(.init(kind: .colorSwap))
        statusText = "Farben getauscht – Du bist Schwarz"
    }

    private func requestSync() {
        peers.send(.init(kind: .syncRequest))
    }

    private func sendSnapshot() {
    let msg = NetMessage(kind: .syncState,
                  move: nil,
                  color: nil,
                  deviceName: peers.localFriendlyName,
                              board: engine.board,
                              sideToMove: engine.sideToMove,
                              movesMade: movesMade,
                              capturedByMe: capturedByMe,
                              capturedByOpponent: capturedByOpponent,
                              lastMoveFrom: lastMove?.from,
                              lastMoveTo: lastMove?.to,
                              lastCapturedPieceID: lastCapturedPieceID,
                              lastCaptureByMe: lastCaptureByMe)
        peers.send(msg)
    }

    private func updateStatusAfterMove() {
        let side = engine.sideToMove
        if engine.isCheckmate(for: side) {
            let winner = side.opposite
            if let me = myColor {
                outcome = (winner == me) ? .win : .loss
                statusText = outcome == .win ? "Du hast gewonnen" : "Du bist Matt"
            } else {
                statusText = "Schachmatt"
            }
        } else if engine.isStalemate(for: side) {
            outcome = .draw
            statusText = "Remis"
        } else if engine.isThreefoldRepetition() {
            outcome = .draw
            statusText = "Remis (dreifache Stellungswiederholung)"
        } else {
            outcome = .ongoing
            statusText = "Am Zug: \(engine.sideToMove == .white ? "Weiß" : "Schwarz")"
        }
    }

    // Determine if a move from->to is a promotion (pawn reaching last rank)
    private func isPromotionMove(from: Square, to: Square) -> Bool {
        guard let piece = engine.board.piece(at: from) else { return false }
        guard piece.type == .pawn else { return false }
        if piece.color == .white && to.rank == 7 { return true }
        if piece.color == .black && to.rank == 0 { return true }
        return false
    }

    // Finalize promotion selection
    func promote(to pieceType: PieceType) {
        guard var base = pendingPromotionMove else { return }
        base = Move(from: base.from, to: base.to, promotion: pieceType)
        let capturedBefore = engine.board.piece(at: base.to)
        if engine.tryMakeMove(base) {
            withAnimation(.easeInOut(duration: 0.35)) {
                if let cap = capturedBefore {
                    if myColor == engine.sideToMove.opposite { // move just made by me
                        capturedByMe.append(cap)
                        lastCapturedPieceID = cap.id
                        lastCaptureByMe = true
                    } else if myColor != nil { // opponent capture path (unlikely here)
                        capturedByOpponent.append(cap)
                        lastCapturedPieceID = cap.id
                        lastCaptureByMe = false
                    }
                } else {
                    lastCapturedPieceID = nil
                    lastCaptureByMe = nil
                }
                movesMade += 1
                lastMove = base
                updateStatusAfterMove()
                if peers.isConnected { peers.send(.init(kind: .move, move: base)) }
            }
        }
        pendingPromotionMove = nil
        showingPromotionPicker = false
    }

    func cancelPromotion() {
        pendingPromotionMove = nil
        showingPromotionPicker = false
    }
}

private extension GameViewModel {
    var isSingleDeviceMode: Bool { !peers.isConnected }
    static func baseName(from composite: String) -> String {
        // Split at first '#' only; if absent return full string
        if let idx = composite.firstIndex(of: "#") {
            return String(composite[..<idx])
        }
        return composite
    }
}
