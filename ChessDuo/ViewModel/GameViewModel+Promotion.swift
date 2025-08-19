//
//  GameViewModel+Promotion.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation
import SwiftUI

extension GameViewModel {
  private func isPromotionMove(from: Square, to: Square) -> Bool {
    guard let piece = engine.board.piece(at: from) else { return false }
    guard piece.type == .pawn else { return false }
    if piece.color == .white && to.rank == 7 { return true }
    if piece.color == .black && to.rank == 0 { return true }
    return false
  }

  func isLegalPromotionMove(from: Square, to: Square) -> Bool {
    guard isPromotionMove(from: from, to: to) else { return false }
    var copy = engine
    let test = Move(from: from, to: to, promotion: .queen)
    return copy.tryMakeMove(test)
  }

  func capturedPieceConsideringEnPassant(from: Square, to: Square, board: Board) -> Piece? {
    if let mover = board.piece(at: from), mover.type == .pawn {
      let df = abs(to.file - from.file)
      if df == 1, to.rank != from.rank, board.piece(at: to) == nil {
        let dir = (mover.color == .white) ? 1 : -1
        let capturedSq = Square(file: to.file, rank: to.rank - dir)
        if let cap = board.piece(at: capturedSq), cap.type == .pawn, cap.color != mover.color { return cap }
      }
    }
    return board.piece(at: to)
  }

  func promote(to pieceType: PieceType) {
    guard var base = pendingPromotionMove else { return }
    base = Move(from: base.from, to: base.to, promotion: pieceType)
    let capturedBefore = engine.board.piece(at: base.to)
    if engine.tryMakeMove(base) {
      withAnimation(.easeInOut(duration: 0.35)) {
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = (myColor == engine.sideToMove.opposite) } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = base
        if peers.isConnected { peers.send(.init(kind: .move, move: base)) }
        moveHistory.append(base)
        historyIndex = nil
        boardSnapshots.append(engine.board)
        saveGame()
        rebuildCapturedLists(for: engine.board)
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
