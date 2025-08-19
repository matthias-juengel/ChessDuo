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
      withAnimation(.easeInOut(duration: 0.35)) {
        peers.send(.init(kind: .move, move: move))
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = true } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = move
        moveHistory.append(move)
        historyIndex = nil
        boardSnapshots.append(engine.board)
        saveGame()
        rebuildCapturedLists(for: engine.board)
      }
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
      withAnimation(.easeInOut(duration: 0.35)) {
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = (moverColor == .white) } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = move
        moveHistory.append(move)
        historyIndex = nil
        boardSnapshots.append(engine.board)
        saveGame()
        rebuildCapturedLists(for: engine.board)
      }
      return true
    }
    return false
  }
}
