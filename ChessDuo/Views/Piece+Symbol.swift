import Foundation

// Centralized chess piece symbol rendering.
// Provides both monochrome (neutral) and colored variants.
// Usage:
//  piece.uiSymbol              -> single set glyph currently using black set for consistency
//  piece.uiSymbol(forColor:)    -> color-aware variant (white vs black unicode)
//  PieceType.symbol(for:)       -> piece type + color
//  PieceType.neutralSymbol()    -> type-only neutral glyph (black set chosen for visual weight)
//
// Rationale: Avoid repeated switch statements across multiple Views.
// Future: Could add theme variations (e.g., text vs SF Symbols vs custom images) behind a strategy.

extension PieceType {
  func symbol(for color: PieceColor) -> String {
    switch self {
    case .king:   return color == .white ? "♔" : "♚"
    case .queen:  return color == .white ? "♕" : "♛"
    case .rook:   return color == .white ? "♖" : "♜"
    case .bishop: return color == .white ? "♗" : "♝"
    case .knight: return color == .white ? "♘" : "♞"
    case .pawn:   return color == .white ? "♙" : "♟︎"
    }
  }
  func neutralSymbol() -> String {
    // Use black-set glyphs for consistency (slightly heavier look improves contrast on light backgrounds)
    switch self {
    case .king: return "♚"
    case .queen: return "♛"
    case .rook: return "♜"
    case .bishop: return "♝"
    case .knight: return "♞"
    case .pawn: return "♟︎"
    }
  }
}

extension Piece {
  var symbol: String { type.neutralSymbol() }
  func symbol(forColorAware aware: Bool) -> String { aware ? type.symbol(for: color) : type.neutralSymbol() }
}
