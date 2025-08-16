import SwiftUI

struct SquareView: View {
  let square: Square
  let piece: Piece?
  let isKingInCheck: Bool
  let isKingCheckmated: Bool
  let rotateForOpponent: Bool
  var lastMoveHighlight: Bool = false

  var body: some View {
    ZStack {
    Rectangle().fill(baseColor())
    if lastMoveHighlight { Rectangle().fill(AppColors.highlightMove) }
      if isKingCheckmated {
        Circle()
          .fill(AppColors.checkmate)
          .padding(3)
        Circle()
          .fill(AppColors.check)
          .padding(6)
      }
      else if isKingInCheck {
        Circle()
          .fill(AppColors.check)
          .padding(3)
      }
      if let p = piece {
        GeometryReader { geo in
          Text(symbol(for: p))
            .font(.system(size: min(geo.size.width, geo.size.height) * 0.75))
            .foregroundColor(p.color == .white ? .white : .black)
            .rotationEffect(rotateForOpponent ? .degrees(180) : .degrees(0))
            .frame(width: geo.size.width, height: geo.size.height)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func baseColor() -> Color {
  return ((square.file + square.rank) % 2 == 0) ? AppColors.boardDark : AppColors.boardLight
  }
  private func symbol(for p: Piece) -> String {
    switch p.type { case .king: return "♚"; case .queen: return "♛"; case .rook: return "♜"; case .bishop: return "♝"; case .knight: return "♞"; case .pawn: return "♟︎" }
  }
}
