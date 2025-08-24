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
      // COLOR NEGOTIATION INVARIANTS
      // Deterministic role assignment uses stableOriginID lexical ordering:
      //  - First contact: smaller stableOriginID becomes White, sends .proposeRole.
      //  - Larger waits; upon seeing .proposeRole (or explicit remote color) becomes Black and replies .acceptRole.
      //  - If both already have same color (race) and no moves yet, recompute deterministically: smaller->White, larger->Black.
      //  - Persisted myColor is kept if movesMade>0 so reconnects don’t flip sides.
      //  - Legacy peers (missing originID) fall back to accepting opposite of any declared color or initiating proposal heuristically.
      // Deterministic color negotiation. Goal: after this (and subsequent propose/accept) sides differ (unless legacy single-device mode).
      let remoteID = msg.originID
      let remoteColor = msg.color
      if let remoteID {
        let a = stableOriginID
        let b = remoteID
        if a == b {
          // Identical IDs (should not happen except in tests if not reset). Force new identity in debug builds.
          #if DEBUG
          _ = _testResetStableIdentity()
          #endif
        }
        let weAreSmaller = stableOriginID < remoteID
        switch (myColor, remoteColor) {
        case (nil, nil):
          // Neither has chosen yet. Smaller becomes white and proposes. Larger stays nil until proposeRole arrives (then picks black).
          if weAreSmaller {
            myColor = .white
            peers.send(.init(kind: .proposeRole))
          } else {
            // remain nil; will adopt black on proposeRole
          }
        case (nil, .some(let rc)):
          // Remote already leaning rc. We adopt opposite and send accept.
            myColor = rc.opposite
            peers.send(.init(kind: .acceptRole))
        case (.some(let lc), nil):
          // We have a color, remote not declaring. If we are white, propose; if black do nothing.
          if lc == .white { peers.send(.init(kind: .proposeRole)) }
        case (.some(let lc), .some(let rc)):
          if lc == rc && movesMade == 0 {
            // Conflict: both same. Recompute deterministically.
            if weAreSmaller {
              myColor = .white
              peers.send(.init(kind: .proposeRole))
            } else {
              myColor = .black
              // Do not send anything; smaller peer already (or will) propose.
            }
          } else if lc != rc {
            // Already complementary -> nothing to do.
          }
        }
      } else {
        // Legacy peer with no origin ID. If they declare a color adopt opposite; else attempt fallback ordering by device name.
        if let rc = remoteColor {
          if myColor == nil { myColor = rc.opposite; peers.send(.init(kind: .acceptRole)) }
          else if myColor == rc { myColor = rc.opposite; peers.send(.init(kind: .proposeRole)) }
        } else {
          attemptRoleProposalIfNeeded()
        }
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
          // Remote move application (animation removed for deterministic test timing).
          if let cap = capturedBefore {
            lastCapturedPieceID = cap.id
            if let my = myColor { lastCaptureByMe = (cap.color != my) } else { lastCaptureByMe = (cap.color == .black) }
            // Archive real captured piece before rebuild so we avoid fabricating placeholder with new UUID.
            if cap.color == .white {
              if !whiteCapturedPieces.contains(where: { $0.id == cap.id }) { whiteCapturedPieces.append(cap) }
            } else {
              if !blackCapturedPieces.contains(where: { $0.id == cap.id }) { blackCapturedPieces.append(cap) }
            }
            // Also update perspective-relative lists immediately (mirrors local move execution logic) so tests see IDs without waiting for rebuild.
            if let my = myColor {
              if cap.color == my { // opponent captured our piece -> appears in capturedByOpponent
                if !capturedByOpponent.contains(where: { $0.id == cap.id }) { capturedByOpponent.append(cap) }
              } else { // opponent lost piece? (shouldn't happen here) else treat as capturedByMe fallback
                if !capturedByMe.contains(where: { $0.id == cap.id }) { capturedByMe.append(cap) }
              }
            } else {
              // Unknown POV yet: default heuristic white piece taken by black means opponent captured our piece if we later become white.
              if cap.color == .white {
                if !capturedByOpponent.contains(where: { $0.id == cap.id }) { capturedByOpponent.append(cap) }
              } else {
                if !capturedByMe.contains(where: { $0.id == cap.id }) { capturedByMe.append(cap) }
              }
            }
          } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
          movesMade += 1
          sessionProgressed = true
          lastMove = m
          moveHistory.append(m)
          historyIndex = nil
          boardSnapshots.append(engine.board)
          // Attribute move to opponent (remote mover). Use originID if provided.
          if let origin = msg.originID, !origin.isEmpty {
            actualParticipants.insert(origin)
          } else if let opp = opponentName, !opp.isEmpty {
            actualParticipants.insert(opp)
          } else if let dev = msg.deviceName { actualParticipants.insert(dev) }
          saveGame()
          rebuildCapturedLists(for: engine.board)
          ensureParticipantsSnapshotIfNeeded(trigger: "remoteMove")
          if peers.isConnected, let mine = myColor, engine.sideToMove == mine { Haptics.trigger(.moveNowMyTurn) }
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
      // Revised participant-policy:
      // 1. A remote progressed multiplayer game (>=2 participants, moves>0) should be ADOPTED by a peer whose local state
      //    is fresh or only single-participant progress, rather than starting a brand new game.
      // 2. We still reject remote progressed snapshots declaring <2 participants (cannot trust identity context).
      // 3. If both sides already have a multiplayer snapshot with different participant sets -> force reset (integrity).
      // 4. Legacy (no participants field) progressed snapshots remain rejected.
      // ADOPTION INVARIANTS (SUMMARY):
      //  - Adoption allowed only if local stableOriginID is present in remote participant list (returning participant) and local has not yet formed a multiplayer snapshot.
      //  - Stranger devices (not in remote set) encountering progressed multiplayer snapshot must reset instead of adopt.
      //  - Dual established but differing participant sets trigger reset on sync to prevent silent fork merging.
      //  - Remote snapshot with moves but <2 participants always rejected (identity insufficient).
      let remoteMoves = msg.movesMade ?? 0
      if let remoteParticipantsRaw = msg.sessionParticipants {
        let remoteParticipants = remoteParticipantsRaw.sorted()
        let localParticipants = currentSessionParticipants(remoteNameHint: nil).sorted()
        if remoteMoves > 0 && remoteParticipants.count < 2 {
          print("[SYNC] Rejecting remote snapshot: remote has moves (\(remoteMoves)) but participants=<2 remote=\(remoteParticipants). Forcing reset (request fresh multiplayer session).")
          performLocalReset(send: true)
          return
        }
        let localHasMulti = localParticipants.count >= 2
        let remoteHasMulti = remoteParticipants.count >= 2
        // ADOPTION POLICY (documented):
        // We adopt a remote multiplayer snapshot only if:
        //  - remoteHasMulti (>=2 participants)
        //  - remoteMoves > 0
        //  - local is fresh OR single-participant (not yet a committed multiplayer snapshot)
        //  - and the local device's stableOriginID is ALREADY in the remote participant list (returning participant)
        // Otherwise:
        //  - If both sides have multiplayer sets and they differ -> reset
        //  - If local is single-participant and NOT in remote list -> treat as mismatch/reset (do NOT adopt stranger game)
        let localID = stableOriginID
        let canAdoptReturning = remoteHasMulti && remoteMoves > 0 && !localHasMulti && remoteParticipants.contains(localID)
        if canAdoptReturning {
          print("[SYNC] Adopting remote multiplayer session as returning participant localID=\(localID) remoteParticipants=\(remoteParticipants)")
          if actualParticipants.isEmpty { actualParticipants.formUnion(remoteParticipants) }
        } else if remoteHasMulti && remoteMoves > 0 && !localHasMulti && !remoteParticipants.contains(localID) {
          print("[SYNC] Rejecting remote multiplayer snapshot (local not a participant) localID=\(localID) remoteParticipants=\(remoteParticipants)")
          performLocalReset(send: true)
          return
        } else if localHasMulti && remoteHasMulti && remoteParticipants != localParticipants {
          print("[SYNC] Multiplayer participant mismatch local=\(localParticipants) remote=\(remoteParticipants) -> forcing reset & ignoring remote snapshot (remoteMoves=\(remoteMoves) localMoves=\(movesMade))")
          performLocalReset(send: true)
          return
        } else {
          print("[SYNC] Participants compatible local=\(localParticipants) remote=\(remoteParticipants) remoteMoves=\(remoteMoves) localMoves=\(movesMade)")
        }
      } else {
        if remoteMoves > 0 {
          print("[SYNC] Rejecting legacy remote snapshot (no participants field) with moves=\(remoteMoves); forcing reset to ensure clean session.")
          performLocalReset(send: true)
          return
        } else {
          print("[SYNC] Legacy remote empty snapshot allowed (no moves, no participants).")
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
        // If remote provided a multiplayer participant list (>=2), adopt it (overwriting a single local participant set)
        if let rp = msg.sessionParticipants, rp.count >= 2 {
          actualParticipants = Set(rp)
        }
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
