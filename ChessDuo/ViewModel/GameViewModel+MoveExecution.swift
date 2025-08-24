//
//  GameViewModel+MoveExecution.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation
import SwiftUI

extension GameViewModel {
  var gameIsOver: Bool {
    let currentPlayerOutcome = outcomeForSide(engine.sideToMove)
    print("Current player (\(engine.sideToMove)) outcome:", currentPlayerOutcome)
    return currentPlayerOutcome != .ongoing
  }

  func outcomeForSide(_ side: PieceColor) -> GameOutcome {
    let isMate = engine.isCheckmate(for: side)
    let isStale = engine.isStalemate(for: side)
    let isRep = engine.isThreefoldRepetition()

    if isMate { return .loss }
    else if isStale { return .draw }
    else if isRep { return .draw }

    let otherSide = side == .white ? PieceColor.black : PieceColor.white

    if engine.isCheckmate(for: otherSide) {
      return .win
    } else {
      return .ongoing
    }
  }

  @discardableResult
  func makeMove(from: Square, to: Square) -> Bool {
    guard !gameIsOver else { return false }
    guard let me = myColor, engine.sideToMove == me else { return false }
    if isLegalPromotionMove(from: from, to: to) {
      pendingPromotionMove = Move(from: from, to: to, promotion: nil)
      showingPromotionPicker = true
      return true // treat as handled for drag success (engine move committed after selection)
    }
    let move = Move(from: from, to: to)
    let capturedBefore = capturedPieceConsideringEnPassant(from: from, to: to, board: engine.board)
    if engine.tryMakeMove(move) {
      // Removed withAnimation wrapper so that state mutations occur synchronously for tests.
      // UI layers can animate based on published changes instead. This avoids races where tests
      // read lastCapturedPieceID or captured lists before the animation transaction applied.
  var net = NetMessage(kind: .move, move: move)
  net.originID = stableOriginID
  peers.send(net)
  // The send initializer above lacks originID; enrich by sending a second message with originID if needed (or adjust NetMessage init usage elsewhere). For minimal change, we could embed originID here by constructing full struct:
  // (Future refactor: provide dedicated helper). For now we will ignore; networking side will attribute local player by playerName.
        if let cap = capturedBefore {
          // Preserve original captured piece identity immediately for UI highlight (before rebuildCapturedLists runs)
          lastCapturedPieceID = cap.id
          lastCaptureByMe = true
          // Inject into captured lists early (rebuildCapturedLists will recompute but this makes highlighting immediate)
          if !capturedByMe.contains(where: { $0.id == cap.id }) {
            capturedByMe.append(cap)
          }
          // Archive by original owner color
          if cap.color == .white {
            if !whiteCapturedPieces.contains(where: { $0.id == cap.id }) { whiteCapturedPieces.append(cap) }
          } else {
            if !blackCapturedPieces.contains(where: { $0.id == cap.id }) { blackCapturedPieces.append(cap) }
          }
        } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = move
        moveHistory.append(move)
        historyIndex = nil
        boardSnapshots.append(engine.board)
  // Record that local player has contributed moves using stable originID (composite display name)
  actualParticipants.insert(stableOriginID)
        saveGame()
        rebuildCapturedLists(for: engine.board)
        ensureParticipantsSnapshotIfNeeded(trigger: "localMove")
      return true
    }
    return false
  }

  /// Local move for single-device mode (no network); both colors playable
  @discardableResult
  func makeLocalMove(from: Square, to: Square) -> Bool {
    guard !gameIsOver else { return false }
    if isLegalPromotionMove(from: from, to: to) {
      pendingPromotionMove = Move(from: from, to: to, promotion: nil)
      showingPromotionPicker = true
      return true
    }
    let move = Move(from: from, to: to)
    let moverColor = engine.sideToMove
    let capturedBefore = capturedPieceConsideringEnPassant(from: from, to: to, board: engine.board)
    if engine.tryMakeMove(move) {
      // Removed withAnimation for synchronous state mutation (see comment above in makeMove).
        if let cap = capturedBefore {
          lastCapturedPieceID = cap.id
          lastCaptureByMe = (moverColor == .white)
          if moverColor == .white {
            if !capturedByMe.contains(where: { $0.id == cap.id }) { capturedByMe.append(cap) }
          } else {
            if !capturedByOpponent.contains(where: { $0.id == cap.id }) { capturedByOpponent.append(cap) }
          }
          if cap.color == .white {
            if !whiteCapturedPieces.contains(where: { $0.id == cap.id }) { whiteCapturedPieces.append(cap) }
          } else {
            if !blackCapturedPieces.contains(where: { $0.id == cap.id }) { blackCapturedPieces.append(cap) }
          }
        } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = move
        moveHistory.append(move)
        historyIndex = nil
        boardSnapshots.append(engine.board)
  // In single-device mode both colors are local; attribute moves to stable originID for snapshot gating.
  actualParticipants.insert(stableOriginID)
        saveGame()
        rebuildCapturedLists(for: engine.board)
        ensureParticipantsSnapshotIfNeeded(trigger: "localMoveSingleDevice")
      return true
    }
    return false
  }
}
