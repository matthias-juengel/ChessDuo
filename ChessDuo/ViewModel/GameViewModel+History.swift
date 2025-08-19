//
//  GameViewModel+History.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation

extension GameViewModel {
  func boardAfterMoves(_ n: Int) -> Board {
    if n < boardSnapshots.count { return boardSnapshots[n] }
    if n == moveHistory.count { return engine.board }
    var e = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    for i in 0..<min(n, moveHistory.count) { _ = e.tryMakeMove(moveHistory[i]) }
    return e.board
  }

  var displayedBoard: Board { historyIndex.map { boardAfterMoves($0) } ?? engine.board }
  var inHistoryView: Bool { historyIndex != nil }

  var displayedSideToMove: PieceColor {
    guard let idx = historyIndex else { return engine.sideToMove }
    return (idx % 2 == 0) ? .white : .black
  }

  func isDisplayedSideInCheck() -> Bool {
    let board = displayedBoard
    let sideToMove = displayedSideToMove
    let tempEngine = ChessEngine.fromSnapshot(board: board, sideToMove: sideToMove)
    return tempEngine.isInCheck(sideToMove)
  }

  func isDisplayedSideCheckmated() -> Bool {
    let board = displayedBoard
    let sideToMove = displayedSideToMove
    let tempEngine = ChessEngine.fromSnapshot(board: board, sideToMove: sideToMove)
    return tempEngine.isCheckmate(for: sideToMove)
  }

  func displayedOutcomeForSide(_ side: PieceColor) -> GameOutcome {
    guard historyIndex != nil else { return outcomeForSide(side) }
    let board = displayedBoard
    let sideToMove = displayedSideToMove
    let tempEngine = ChessEngine.fromSnapshot(board: board, sideToMove: sideToMove)
    let isMate = tempEngine.isCheckmate(for: side)
    let isStale = tempEngine.isStalemate(for: side)
    if isMate { return .loss }
    else if isStale { return .draw }
    let otherSide = side == .white ? PieceColor.black : PieceColor.white
    if tempEngine.isCheckmate(for: otherSide) { return .win } else { return .ongoing }
  }

  func pointAdvantage(forMe: Bool) -> Int {
    let myPoints = capturedByMe.reduce(0) { $0 + pieceValue($1) }
    let opponentPoints = capturedByOpponent.reduce(0) { $0 + pieceValue($1) }
    return forMe ? (myPoints - opponentPoints) : (opponentPoints - myPoints)
  }

  func historicalPointAdvantage(forMe: Bool) -> Int {
    guard let idx = historyIndex else { return pointAdvantage(forMe: forMe) }
    let board = boardAfterMoves(idx)
    let (whiteMissing, blackMissing) = missingComparedToBaseline(current: board)
    func points(from missing: [PieceType:Int]) -> Int {
      missing.reduce(0) { partial, kv in
        let (type, count) = kv
        let value: Int
        switch type { case .queen: value = 9; case .rook: value = 5; case .bishop, .knight: value = 3; case .pawn: value = 1; case .king: value = 0 }
        return partial + value * count
      }
    }
    let whiteCapturedPoints = points(from: blackMissing)
    let blackCapturedPoints = points(from: whiteMissing)
    if let my = myColor {
      let myPts = (my == .white) ? whiteCapturedPoints : blackCapturedPoints
      let oppPts = (my == .white) ? blackCapturedPoints : whiteCapturedPoints
      return forMe ? (myPts - oppPts) : (oppPts - myPts)
    } else {
      let myPts = forMe ? whiteCapturedPoints : blackCapturedPoints
      let oppPts = forMe ? blackCapturedPoints : whiteCapturedPoints
      return (myPts - oppPts)
    }
  }

  // Kept fileprivate scope already available in base file; duplicate left internal here for clarity.
  private func pieceValue(_ piece: Piece) -> Int {
    switch piece.type {
    case .queen: return 9
    case .rook: return 5
    case .bishop, .knight: return 3
    case .pawn: return 1
    case .king: return 0
    }
  }
}
