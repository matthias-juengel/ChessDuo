//
//  GameViewModel+Networking.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation
import SwiftUI

extension GameViewModel {
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

  func handle(_ msg: NetMessage) { // internal for callback from base init
    switch msg.kind {
    case .hello:
      if myColor == nil, let remoteColor = msg.color {
        myColor = remoteColor.opposite
        peers.send(.init(kind: .acceptRole))
      } else if let mine = myColor, let remoteColor = msg.color, mine == remoteColor {
        if movesMade > 0, mine == .white {
          peers.send(.init(kind: .proposeRole))
        } else if mine == .white {
          myColor = .black
          peers.send(.init(kind: .acceptRole))
        }
      } else {
        attemptRoleProposalIfNeeded()
      }
      requestSync()
    case .reset:
      engine.reset()
      capturedByMe.removeAll()
      capturedByOpponent.removeAll()
  whiteCapturedPieces.removeAll()
  blackCapturedPieces.removeAll()
  fabricatedCapturedPieceIDs.removeAll()
      movesMade = 0
      awaitingResetConfirmation = false
      incomingResetRequest = false
      lastMove = nil
      lastCapturedPieceID = nil
      lastCaptureByMe = nil
    case .move:
      if let m = msg.move {
        let capturedBefore = capturedPieceConsideringEnPassant(from: m.from, to: m.to, board: engine.board)
        if !gameIsOver, engine.tryMakeMove(m) {
          withAnimation(.easeInOut(duration: 0.35)) {
            if let cap = capturedBefore {
              lastCapturedPieceID = cap.id
              if let my = myColor { lastCaptureByMe = (cap.color != my) } else { lastCaptureByMe = (cap.color == .black) }
            } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
            movesMade += 1
            sessionProgressed = true
            lastMove = m
            moveHistory.append(m)
            historyIndex = nil
            boardSnapshots.append(engine.board)
            // Attribute move to opponent (remote mover). Use opponentName if known, else msg.deviceName.
            if let origin = msg.originID, !origin.isEmpty {
              actualParticipants.insert(origin)
            } else if let opp = opponentName, !opp.isEmpty {
              actualParticipants.insert(opp)
            } else if let dev = msg.deviceName { // legacy fallback
              actualParticipants.insert(dev)
            }
            saveGame()
            rebuildCapturedLists(for: engine.board)
            ensureParticipantsSnapshotIfNeeded(trigger: "remoteMove")
            if peers.isConnected, let mine = myColor, engine.sideToMove == mine {
              Haptics.trigger(.moveNowMyTurn)
            }
          }
        }
      }
    case .proposeRole:
      if myColor == nil {
        myColor = .black
        peers.send(.init(kind: .acceptRole))
      } else if myColor == .white && movesMade == 0 {
        myColor = .black
        peers.send(.init(kind: .acceptRole))
      }
    case .acceptRole:
      if myColor == nil { myColor = .white }
    case .requestReset:
      incomingResetRequest = true
      awaitingResetConfirmation = false
    case .acceptReset:
      performLocalReset(send: true)
    case .declineReset:
      awaitingResetConfirmation = false
      incomingResetRequest = false
    case .syncRequest:
      sendSnapshot()
    case .syncState:
      // Participant-aware gating: if sender's participants differ from ours, force a reset (Option A) and ignore snapshot.
      if let remoteParticipantsRaw = msg.sessionParticipants {
        let remoteParticipants = remoteParticipantsRaw
        let localParticipants = currentSessionParticipants(remoteNameHint: nil)
        // Only adopt a progressed remote snapshot if it represents a multiplayer session (>=2 participants).
        if (msg.movesMade ?? 0) > 0 && remoteParticipants.count < 2 {
          print("[SYNC] Rejecting remote snapshot: remote has moves (\(msg.movesMade ?? -1)) but participants=<2 remote=\(remoteParticipants). Forcing reset to start fresh multiplayer session.")
          performLocalReset(send: true)
          return
        }
        // If our local progressed game is still single-participant, we also force a reset when a conflicting snapshot arrives.
        if movesMade > 0 && localParticipants.count < 2 && (msg.movesMade ?? 0) > 0 {
          print("[SYNC] Local progressed single-participant game detected; forcing reset to ensure clean multiplayer context.")
          performLocalReset(send: true)
          return
        }
        if remoteParticipants.sorted() != localParticipants.sorted() {
          print("[SYNC] Participant mismatch local=\(localParticipants) remote=\(remoteParticipants) -> forcing reset & ignoring remote snapshot (remoteMoves=\(msg.movesMade ?? -1) localMoves=\(movesMade))")
          performLocalReset(send: true)
          return
        } else {
          print("[SYNC] Participants match local=\(localParticipants) remote=\(remoteParticipants) remoteMoves=\(msg.movesMade ?? -1) localMoves=\(movesMade)")
        }
      } else {
        // Legacy peer: if it tries to push progressed state without participant metadata, reject (cannot safely verify identity context)
        if let rm = msg.movesMade, rm > 0 {
          print("[SYNC] Rejecting legacy remote snapshot (no participants field) with moves=\(rm); forcing reset to ensure clean session.")
          performLocalReset(send: true)
          return
        } else {
          print("[SYNC] Legacy remote snapshot without participants (no moves) allowing only if empty.")
        }
      }
      if let remoteMoves = msg.movesMade, remoteMoves > movesMade,
         let b = msg.board,
         let stm = msg.sideToMove,
         let remoteCapturedBySender = msg.capturedByMe,
         let remoteCapturedByOpponent = msg.capturedByOpponent {
        print("[SYNC] Adopting remote snapshot remoteMoves=\(remoteMoves) > localMoves=\(movesMade) sideToMove=\(stm) lastMoveFrom=\(String(describing: msg.lastMoveFrom)) lastMoveTo=\(String(describing: msg.lastMoveTo)))")
        engine = ChessEngine.fromSnapshot(board: b, sideToMove: stm)
        capturedByOpponent = remoteCapturedBySender
        capturedByMe = remoteCapturedByOpponent
        movesMade = remoteMoves
        if let from = msg.lastMoveFrom, let to = msg.lastMoveTo { lastMove = Move(from: from, to: to) } else { lastMove = nil }
        if let capID = msg.lastCapturedPieceID, let bySender = msg.lastCaptureByMe {
          lastCapturedPieceID = capID
          lastCaptureByMe = !bySender
        } else {
          lastCapturedPieceID = nil
          lastCaptureByMe = nil
        }
        if let remoteHistory = msg.moveHistory {
          moveHistory = remoteHistory
          historyIndex = nil
          boardSnapshots = []
          rebuildSnapshotsFromHistory()
        }
        // Attempt to infer actual participants from remote snapshot participant metadata (only if we have none yet)
        if actualParticipants.isEmpty, let rp = msg.sessionParticipants, rp.count >= 2 {
          actualParticipants.formUnion(rp)
        }
        ensureParticipantsSnapshotIfNeeded(trigger: "adoptRemoteSnapshot")
      } else if let remoteMoves = msg.movesMade, remoteMoves < movesMade {
        print("[SYNC] Remote has fewer moves (remote=\(remoteMoves) < local=\(movesMade)) -> sending our snapshot back")
        sendSnapshot()
      }
    case .colorSwap:
      if movesMade == 0, let current = myColor { myColor = current.opposite }
    case .requestHistoryRevert:
      if let target = msg.revertToCount {
        incomingHistoryRevertRequest = target
        awaitingHistoryRevertConfirmation = false
        requestedHistoryRevertTarget = nil
      }
    case .acceptHistoryRevert:
      if let target = msg.revertToCount {
        performHistoryRevert(to: target, send: true)
        awaitingHistoryRevertConfirmation = false
        requestedHistoryRevertTarget = nil
      }
    case .declineHistoryRevert:
      awaitingHistoryRevertConfirmation = false
      incomingHistoryRevertRequest = nil
      requestedHistoryRevertTarget = nil
    case .revertHistory:
      if let target = msg.revertToCount { performHistoryRevert(to: target, send: false) }
    case .historyView:
      if let remoteIdx = msg.historyViewIndex {
        if remoteIdx >= 0 && remoteIdx <= moveHistory.count && remoteIdx != moveHistory.count {
          suppressHistoryViewBroadcast = true
            remoteIsDrivingHistoryView = true
            historyIndex = remoteIdx
          suppressHistoryViewBroadcast = false
        }
      } else {
        if remoteIsDrivingHistoryView {
          suppressHistoryViewBroadcast = true
          remoteIsDrivingHistoryView = false
          historyIndex = nil
          suppressHistoryViewBroadcast = false
        }
      }
    case .requestLoadGame:
      incomingLoadGameRequestTitle = msg.gameTitle
      awaitingLoadGameConfirmation = false
    case .acceptLoadGame:
      if let game = pendingGameToLoad {
        applyFamousGame(game, broadcast: true)
        pendingGameToLoad = nil
      }
      awaitingLoadGameConfirmation = false
    case .declineLoadGame:
      awaitingLoadGameConfirmation = false
      pendingGameToLoad = nil
      incomingLoadGameRequestTitle = nil
    case .loadGameState:
      if let b = msg.board,
         let stm = msg.sideToMove,
         let remoteMoves = msg.movesMade,
         let remoteCapturedBySender = msg.capturedByMe,
         let remoteCapturedByOpponent = msg.capturedByOpponent,
         let remoteHistory = msg.moveHistory {
        // If an initialFEN was provided, use it to reconstruct baseline (even if board snapshot is also sent) so
        // subsequent history reconstruction & capture logic align with sender's baseline.
        if let fen = msg.initialFEN, let baselineEngine = ChessEngine.fromFEN(fen) {
          baselineBoard = baselineEngine.board
          baselineSideToMove = baselineEngine.sideToMove
          baselineCounts = pieceCounts(on: baselineBoard)
          baselineTrusted = true
        } else {
          // Fallback: treat incoming board AFTER all moves as authoritative and derive baseline from applying history to a fresh engine.
          // (Existing logic below rebuilds snapshots from moveHistory and will preserve baseline fields if already set.)
          // If we had no moves yet, set a standard baseline so rebuild logic is consistent.
          if remoteHistory.isEmpty {
            baselineBoard = Board.initial()
            baselineSideToMove = .white
            baselineCounts = pieceCounts(on: baselineBoard)
            baselineTrusted = true
          }
        }
        engine = ChessEngine.fromSnapshot(board: b, sideToMove: stm)
        capturedByOpponent = remoteCapturedBySender
        capturedByMe = remoteCapturedByOpponent
        movesMade = remoteMoves
        moveHistory = remoteHistory
        lastMove = msg.lastMoveFrom.flatMap { from in msg.lastMoveTo.map { Move(from: from, to: $0) } }
        lastCapturedPieceID = msg.lastCapturedPieceID
        lastCaptureByMe = msg.lastCaptureByMe.map { !$0 }
        historyIndex = nil
        remoteIsDrivingHistoryView = false
        boardSnapshots = []
        rebuildSnapshotsFromHistory()
        saveGame()
        sessionProgressed = false
      }
    }
  }

  func attemptRoleProposalIfNeeded() { // internal so base file can trigger
    guard myColor == nil, let first = peers.connectedPeers.first else { return }
    let iAmWhite = peers.localDisplayName < first.displayName
    if iAmWhite {
      myColor = .white
      peers.send(.init(kind: .proposeRole))
    }
  }

  func respondToIncomingInvitation(_ accept: Bool) {
    pendingInvitationDecision?(accept)
    pendingInvitationDecision = nil
    incomingJoinRequestPeer = nil
  }

  func swapColorsIfAllowed() {
    guard movesMade == 0, let me = myColor, me == .white else { return }
    myColor = .black
    peers.send(.init(kind: .colorSwap))
    preferredPerspective = .black
  }

  func requestSync() { peers.send(.init(kind: .syncRequest)) }

  func sendSnapshot() {
    let participants = currentSessionParticipants(remoteNameHint: nil)
    print("[SYNC] Sending snapshot moves=\(movesMade) sideToMove=\(engine.sideToMove) participants=\(participants) lastMove=\(String(describing: lastMove)) historyCount=\(moveHistory.count)")
    let msg = NetMessage(kind: .syncState,
                         move: nil,
                         color: nil,
                         deviceName: playerName,
                         board: engine.board,
                         sideToMove: engine.sideToMove,
                         movesMade: movesMade,
                         capturedByMe: capturedByMe,
                         capturedByOpponent: capturedByOpponent,
                         lastMoveFrom: lastMove?.from,
                         lastMoveTo: lastMove?.to,
                         lastCapturedPieceID: lastCapturedPieceID,
                         lastCaptureByMe: lastCaptureByMe,
                         moveHistory: moveHistory,
                         sessionParticipants: participants,
                         originID: stableOriginID)
    peers.send(msg)
  }
}

// MARK: - Participant Tracking
extension GameViewModel {
  /// Returns the sorted list of participant player names for the current session (1 or 2 entries).
  /// Includes local player name and any connected opponent name (first). Fallback to remoteNameHint if
  /// connection list not yet populated during early sync handshake.
  func currentSessionParticipants(remoteNameHint: String?) -> [String] {
    if let snap = sessionParticipantsSnapshot { return snap }
    if !actualParticipants.isEmpty { return Array(actualParticipants).sorted() }
    // Fall back to stable origin ID (single participant baseline)
    return [stableOriginID]
  }
}

// MARK: - Participant Snapshot Invariants
// Invariants enforced across networking & persistence layers (validated by unit tests):
// 1. A participants snapshot (sessionParticipantsSnapshot) is captured only after two distinct origin IDs have made moves.
//    - Single-side progress (local or remote) must NOT create a snapshot; tests: testSingleSideMoveDoesNotCaptureParticipantsSnapshot.
// 2. Once captured (>=2 participants), the snapshot is treated as immutable identity context for the session.
//    - Incoming syncState with a different participant set triggers a forced reset (participantMismatchForcesReset).
// 3. A progressed remote snapshot (movesMade > 0) that declares <2 participants is rejected and causes a reset (soloRemoteProgressedSnapshotIsRejected).
// 4. Legacy peers (no participants field) cannot push progressed state (moves>0); such attempts are rejected to avoid identity spoofing.
// 5. Snapshot persists across app restarts and prevents unwarranted resets when syncing identical participant sets (testReconnectionPersistsTwoParticipantsAndAvoidsReset, testRestartPreservesParticipantsAndAvoidsResetOnSync).
// 6. Remote adoption path can hydrate actualParticipants only if we currently have none and remote provides a >=2 participant list.
// Any change to these rules should update corresponding tests to maintain security & integrity guarantees.
