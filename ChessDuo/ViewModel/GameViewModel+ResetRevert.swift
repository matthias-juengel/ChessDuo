//
//  GameViewModel+ResetRevert.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation

extension GameViewModel {
  func performLocalReset(send: Bool) {
    engine.reset()
    capturedByMe.removeAll()
    capturedByOpponent.removeAll()
  // Clear archival capture data so a brand new session has no stale identities preventing first highlight
  whiteCapturedPieces.removeAll()
  blackCapturedPieces.removeAll()
  fabricatedCapturedPieceIDs.removeAll()
    movesMade = 0
    awaitingResetConfirmation = false
    incomingResetRequest = false
    offlineResetPrompt = false
    lastMove = nil
    lastCapturedPieceID = nil
    lastCaptureByMe = nil
    moveHistory = []
    historyIndex = nil
    sessionProgressed = false
    boardSnapshots = [engine.board]
    baselineBoard = engine.board
    baselineSideToMove = engine.sideToMove
    baselineCounts = pieceCounts(on: baselineBoard)
    baselineTrusted = true
    rebuildCapturedLists(for: engine.board)
    if send { peers.send(.init(kind: .reset)) }
    saveGame()
  }

  func respondToResetRequest(accept: Bool) {
    if accept {
      peers.send(.init(kind: .acceptReset))
      performLocalReset(send: true)
    } else {
      peers.send(.init(kind: .declineReset))
      incomingResetRequest = false
      awaitingResetConfirmation = false
    }
  }

  // MARK: - History Revert Logic
  func requestHistoryRevert(to target: Int) {
    guard target >= 0, target <= moveHistory.count else { return }
    if peers.isConnected {
      if target == moveHistory.count { return }
      awaitingHistoryRevertConfirmation = true
      incomingHistoryRevertRequest = nil
      requestedHistoryRevertTarget = target
      peers.send(.init(kind: .requestHistoryRevert, revertToCount: target))
    } else {
      performHistoryRevert(to: target, send: false)
    }
  }

  func respondToHistoryRevertRequest(accept: Bool) {
    guard let target = incomingHistoryRevertRequest else { return }
    if accept {
      peers.send(.init(kind: .acceptHistoryRevert, revertToCount: target))
    } else {
      peers.send(.init(kind: .declineHistoryRevert, revertToCount: target))
    }
    incomingHistoryRevertRequest = nil
  }

  func performHistoryRevert(to target: Int, send: Bool) {
    guard target >= 0, target <= moveHistory.count else { return }
    var e = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    var newCapturedByMe: [Piece] = []
    var newCapturedByOpponent: [Piece] = []
    var lastCapID: UUID? = nil
    var lastCapByMe: Bool? = nil
    var newLastMove: Move? = nil
    for i in 0..<target {
      let mv = moveHistory[i]
      let captured: Piece? = capturedPieceConsideringEnPassant(from: mv.from, to: mv.to, board: e.board)
      _ = e.tryMakeMove(mv)
      if let cap = captured {
        if let my = myColor {
          if cap.color == my { newCapturedByOpponent.append(cap); lastCapByMe = false }
          else { newCapturedByMe.append(cap); lastCapByMe = true }
        } else {
          if cap.color == .black { newCapturedByMe.append(cap); lastCapByMe = true } else { newCapturedByOpponent.append(cap); lastCapByMe = false }
        }
        lastCapID = cap.id
      }
      newLastMove = mv
    }
    engine = e
    capturedByMe = newCapturedByMe
    capturedByOpponent = newCapturedByOpponent
    movesMade = target
    lastMove = newLastMove
    lastCapturedPieceID = lastCapID
    lastCaptureByMe = lastCapByMe
    if target < moveHistory.count { moveHistory = Array(moveHistory.prefix(target)) }
    sessionProgressed = target > 0
    let prevSuppress = suppressHistoryViewBroadcast
    suppressHistoryViewBroadcast = true
    historyIndex = nil
    remoteIsDrivingHistoryView = false
    suppressHistoryViewBroadcast = prevSuppress
    boardSnapshots = [ChessEngine().board]
    var rebuildEngine = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    for mv in moveHistory { _ = rebuildEngine.tryMakeMove(mv); boardSnapshots.append(rebuildEngine.board) }
    saveGame()
    if send { peers.send(.init(kind: .revertHistory, revertToCount: target)) }
    lastAppliedHistoryRevertTarget = target
    awaitingHistoryRevertConfirmation = false
    incomingHistoryRevertRequest = nil
    requestedHistoryRevertTarget = nil
    rebuildCapturedLists(for: engine.board)
  }

  func cancelPendingHistoryRevertRequest() {
    guard awaitingHistoryRevertConfirmation, let target = requestedHistoryRevertTarget else { return }
    awaitingHistoryRevertConfirmation = false
    peers.send(.init(kind: .declineHistoryRevert, revertToCount: target))
    requestedHistoryRevertTarget = nil
  }

  func acknowledgeAppliedHistoryRevert() { /* placeholder */ }
}
