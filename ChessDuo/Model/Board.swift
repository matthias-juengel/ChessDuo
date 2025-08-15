//
//  Board.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//

import Foundation

struct Board: Codable, Equatable {
  // 8x8, index = rank*8 + file
  private(set) var cells: [Piece?] = Array(repeating: nil, count: 64)
  
  static func index(_ s: Square) -> Int { s.rank * 8 + s.file }
  func piece(at s: Square) -> Piece? { cells[Board.index(s)] }
  
  mutating func set(_ p: Piece?, at s: Square) {
    cells[Board.index(s)] = p
  }
  
  static func initial() -> Board {
    var b = Board()
    let back: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
    // White pieces (rank 0,1)
    for f in 0..<8 {
      b.set(Piece(type: .pawn, color: .white), at: .init(file: f, rank: 1))
      b.set(Piece(type: back[f], color: .white), at: .init(file: f, rank: 0))
    }
    // Black pieces (rank 7,6)
    for f in 0..<8 {
      b.set(Piece(type: .pawn, color: .black), at: .init(file: f, rank: 6))
      b.set(Piece(type: back[f], color: .black), at: .init(file: f, rank: 7))
    }
    return b
  }
  
  static func inBounds(_ s: Square) -> Bool {
    (0...7).contains(s.file) && (0...7).contains(s.rank)
  }
}
