//
//  GameViewModel+Captures.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation

extension GameViewModel {
  func historicalCaptureHighlight(at historyIndex: Int) -> (pieceID: UUID, byMe: Bool)? {
    guard historyIndex > 0, historyIndex <= moveHistory.count else { return nil }
    var engine = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    for i in 0..<(historyIndex - 1) { _ = engine.tryMakeMove(moveHistory[i]) }
    let move = moveHistory[historyIndex - 1]
    guard let cap = capturedPiece(beforeApplying: move, on: engine.board) else { return nil }
    _ = engine.tryMakeMove(move)
    let capturedByWhite = cap.color == .black
    let byMe: Bool = { if let my = myColor { return (my == .white) == capturedByWhite }; return capturedByWhite }()
    return (cap.id, byMe)
  }

  func captureReconstruction(at historyIndex: Int) -> (whiteCaptures: [Piece], blackCaptures: [Piece], lastCapturePieceID: UUID?, lastCapturingSide: PieceColor?) {
    let clamped = max(0, min(historyIndex, moveHistory.count))
    var engine = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    var capsByWhite: [Piece] = []
    var capsByBlack: [Piece] = []
    var lastCapID: UUID? = nil
    var lastCapturingSide: PieceColor? = nil
    if clamped == 0 { return (capsByWhite, capsByBlack, nil, nil) }
    for i in 0..<clamped {
      let mv = moveHistory[i]
      let captured = capturedPiece(beforeApplying: mv, on: engine.board)
      _ = engine.tryMakeMove(mv)
      if let cap = captured {
        if cap.color == .white { capsByBlack.append(cap); lastCapturingSide = .black }
        else { capsByWhite.append(cap); lastCapturingSide = .white }
        lastCapID = cap.id
      }
    }
    return (capsByWhite, capsByBlack, lastCapID, lastCapturingSide)
  }
}

private extension GameViewModel {
  func capturedPiece(beforeApplying move: Move, on board: Board) -> Piece? {
    if let piece = board.piece(at: move.to) { return piece }
    if let moving = board.piece(at: move.from), moving.type == .pawn, move.from.file != move.to.file, board.piece(at: move.to) == nil {
      let dir = moving.color == .white ? 1 : -1
      let capturedSq = Square(file: move.to.file, rank: move.to.rank - dir)
      if let epPawn = board.piece(at: capturedSq), epPawn.color != moving.color, epPawn.type == .pawn { return epPawn }
    }
    return nil
  }
}

internal extension GameViewModel {
  func rebuildSnapshotsFromHistory() {
    if boardSnapshots.count == moveHistory.count + 1 { return }
    guard baselineTrusted else {
      if boardSnapshots.isEmpty { boardSnapshots = [engine.board] }
      return
    }
    var e = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    var newSnapshots: [Board] = [baselineBoard]
    for mv in moveHistory { _ = e.tryMakeMove(mv); newSnapshots.append(e.board) }
    if let last = newSnapshots.last, !boardsEqual(last, engine.board) {
      engine = ChessEngine.fromSnapshot(board: last, sideToMove: (moveHistory.count % 2 == 0) ? baselineSideToMove : baselineSideToMove.opposite)
    }
    boardSnapshots = newSnapshots
  }

  private func boardsEqual(_ a: Board, _ b: Board) -> Bool {
    for rank in 0..<8 { for file in 0..<8 {
      let sq = Square(file: file, rank: rank)
      let pa = a.piece(at: sq)
      let pb = b.piece(at: sq)
      if pa?.type != pb?.type || pa?.color != pb?.color { return false }
    }}
    return true
  }
}
