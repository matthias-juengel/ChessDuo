import SwiftUI

struct PromotionPickerView: View {
  let color: PieceColor
  var rotate180: Bool = false
  let onSelect: (PieceType) -> Void
  let onCancel: () -> Void
  private let choices: [PieceType] = [.queen, .rook, .bishop, .knight]
  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .ignoresSafeArea()
        .onTapGesture { onCancel() }
        .accessibilityHidden(true)
      VStack(spacing: 16) {
        Text(String.loc("promote_choose"))
          .font(.title2).bold()
          .foregroundColor(.white)
        HStack(spacing: 20) {
          ForEach(choices, id: \.self) { pt in
            Button(action: {
#if canImport(UIKit)
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
              onSelect(pt)
            }) {
              Text(symbol(for: pt, color: color))
                .font(.system(size: 48))
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: pt))
            .accessibilityAddTraits(.isButton)
          }
        }
        Button(String.loc("cancel")) { onCancel() }
          .font(.title3)
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
          .background(Color.white.opacity(0.85))
          .foregroundColor(.black)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .padding(30)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
    }
    .rotationEffect(rotate180 ? .degrees(180) : .degrees(0))
  }
  private func symbol(for t: PieceType, color: PieceColor) -> String {
    switch t {
    case .queen: return color == .white ? "♕" : "♛"
    case .rook: return color == .white ? "♖" : "♜"
    case .bishop: return color == .white ? "♗" : "♝"
    case .knight: return color == .white ? "♘" : "♞"
    case .king: return color == .white ? "♔" : "♚"
    case .pawn: return color == .white ? "♙" : "♟︎"
    }
  }

  private func accessibilityLabel(for t: PieceType) -> String {
    let pieceName: String
    switch t {
    case .queen: pieceName = String.loc("piece_queen")
    case .rook: pieceName = String.loc("piece_rook")
    case .bishop: pieceName = String.loc("piece_bishop")
    case .knight: pieceName = String.loc("piece_knight")
    case .king: pieceName = String.loc("piece_king")
    case .pawn: pieceName = String.loc("piece_pawn")
    }
    let colorName = color == .white ? String.loc("color_white") : String.loc("color_black")
    // Fallback English if localization keys absent.
    let combined = String.loc("promote_accessibility", pieceName, colorName)
    return combined
  }
}
