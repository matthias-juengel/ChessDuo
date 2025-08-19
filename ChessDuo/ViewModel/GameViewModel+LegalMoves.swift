//
//  GameViewModel+LegalMoves.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation

extension GameViewModel {
  func legalDestinations(from: Square) -> Set<Square> {
    if historyIndex != nil { return [] }
    guard let piece = engine.board.piece(at: from) else { return [] }
    if peers.isConnected, let mine = myColor, engine.sideToMove != mine { return [] }
    if piece.color != engine.sideToMove { return [] }
    let sig = boardSignature()
    if lastCacheBoardSignature != sig {
      legalDestCache.removeAll()
      lastCacheBoardSignature = sig
    }
    let cacheKey = sig + "|f" + String(from.file) + "r" + String(from.rank)
    if let cached = legalDestCache[cacheKey] { return cached }
    let moves = engine.generateLegalMoves(for: engine.sideToMove)
    let dests = Set(moves.filter { $0.from == from }.map { $0.to })
    legalDestCache[cacheKey] = dests
    return dests
  }

  func loadFamousGame(_ game: FamousGame) {
  // Delegate to unified famous game loader (no broadcast from this legacy entry point)
  applyFamousGame(game, broadcast: false)
  }
}

// MARK: - Board Signature
internal extension GameViewModel {
  func boardSignature() -> String {
    var s = String(); s.reserveCapacity(8*8*2 + 1)
    for rank in 0..<8 { for file in 0..<8 {
      let sq = Square(file: file, rank: rank)
      if let p = engine.board.piece(at: sq) {
        let c = (p.color == .white ? "W" : "B")
        let t = String(p.type.rawValue.first!)
        s.append(c); s.append(t)
      } else { s.append("__") }
    }}
    s.append(engine.sideToMove == .white ? "w" : "b")
    return s
  }
}
