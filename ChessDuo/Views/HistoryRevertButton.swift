import SwiftUI

/// Floating button shown while scrubbing history allowing user to restart game from that position.
struct HistoryRevertButton: View {
  let index: Int // number of moves currently applied in preview
  let total: Int
  let onConfirm: (Int) -> Void // passes target move count to keep
  let cancelHistory: () -> Void

  var body: some View {
    GeometryReader { geo in
      let size: CGFloat = 46
      let padding: CGFloat = 14
      HStack(spacing: 12) {
        // Revert button (left of menu button location)
        Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { onConfirm(index) } }) {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String.loc("history_revert_button"))

        // Close history (X) button for convenience
        Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { cancelHistory() } }) {
          Image(systemName: "xmark")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String.loc("history_close_button"))
      }
      .shadow(color: AppColors.shadowCard.opacity(0.6), radius: 8, x: 0, y: 4)
      .position(x: geo.size.width - padding - size/2 - size - 12, // to left of menu button
                y: geo.size.height - padding - size/2)
      .zIndex(OverlayZIndex.menu + 0.5)
      .animation(.spring(response: 0.35, dampingFraction: 0.82), value: index)
    }
    .allowsHitTesting(true)
  }
}
