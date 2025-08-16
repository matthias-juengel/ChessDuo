import SwiftUI

struct PromotionPickerView: View {
  let color: PieceColor
  var rotate180: Bool = false
  let onSelect: (PieceType) -> Void
  let onCancel: () -> Void
  private let choices: [PieceType] = [.queen, .rook, .bishop, .knight]
  var body: some View {
  VStack(spacing: 16) {
        Text(String.loc("promote_choose"))
          .font(.title2).bold()
          .foregroundColor(AppColors.textPrimary)
        HStack(spacing: 14) { // tighter spacing to fit small widths
          ForEach(choices, id: \.self) { pt in
            Button(action: {
#if canImport(UIKit)
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
              onSelect(pt)
            }) {
              // Enlarged piece symbol; slightly reduced container to decrease empty padding.
              // Layout math (smallest width target ~320): 4 * 52 + 3 * 14 = 250 + card horizontal padding (2*24) = 298 < 320.
              Text(symbol(for: pt, color: color))
                .font(.system(size: 34))
                .minimumScaleFactor(0.6) // allow slight shrink on very small accessibility sizes
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.buttonSymbolBG))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: pt))
            .accessibilityAddTraits(.isButton)
          }
        }
        Button(String.loc("cancel")) { onCancel() }
          .buttonStyle(.modal(role: .primary))
  }
  // Remove large outer padding; ModalCard already provides internal padding
  .padding(.top, 6)
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
