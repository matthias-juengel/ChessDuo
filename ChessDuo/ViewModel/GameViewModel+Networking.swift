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
            saveGame()
            rebuildCapturedLists(for: engine.board)
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
      if let remoteMoves = msg.movesMade, remoteMoves > movesMade,
         let b = msg.board,
         let stm = msg.sideToMove,
         let remoteCapturedBySender = msg.capturedByMe,
         let remoteCapturedByOpponent = msg.capturedByOpponent {
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
      } else if let remoteMoves = msg.movesMade, remoteMoves < movesMade {
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
                         moveHistory: moveHistory)
    peers.send(msg)
  }
}
