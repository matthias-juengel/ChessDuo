import SwiftUI

struct SquareView: View {
  let square: Square
  let piece: Piece?
  let isSelected: Bool
  let isKingInCheck: Bool
  let isKingCheckmated: Bool
  let rotateForOpponent: Bool
  var lastMoveHighlight: Bool = false

  var body: some View {
    ZStack {
      Rectangle().fill(baseColor())
      if lastMoveHighlight { Rectangle().fill(Color.green.opacity(0.45)) }
      if isKingInCheck {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isKingCheckmated ? Color.red.opacity(0.9) : Color.orange.opacity(0.7))
          .padding(4)
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
    let grayBlack = Color(red: 0.4, green: 0.4, blue: 0.4)
    let grayWhite = Color(red: 0.6, green: 0.6, blue: 0.6)
    return ((square.file + square.rank) % 2 == 0) ? grayBlack : grayWhite
  }
  private func symbol(for p: Piece) -> String {
    switch p.type { case .king: return "♚"; case .queen: return "♛"; case .rook: return "♜"; case .bishop: return "♝"; case .knight: return "♞"; case .pawn: return "♟︎" }
  }
}
