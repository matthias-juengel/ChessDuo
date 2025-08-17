import SwiftUI

/// Shows the menu button in normal play; in history view shows a revert button with text and a close (X) to exit history.
struct CombinedFloatingButtons: View {
  @ObservedObject var vm: GameViewModel
  let availability: GameMenuButtonOverlay.Availability
  @Binding var showMenu: Bool
  let onHideHistory: () -> Void

  var body: some View {
    GeometryReader { geo in
      let size: CGFloat = 46
      let padding: CGFloat = 14
      HStack(spacing: 12) {
        if let idx = vm.historyIndex { // History mode buttons
          Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
              vm.requestHistoryRevert(to: idx)
            }
          }) {
            HStack(spacing: 8) {
              Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 18, weight: .semibold))
              Text(String.loc("history_revert_short"))
                .font(.callout.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: size)
            .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String.loc("history_revert_button"))

          Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { onHideHistory() } }) {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.white)
              .frame(width: size, height: size)
              .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String.loc("history_close_button"))
        } else if availability.isEmpty == false { // Normal menu button only when NOT in history mode
          Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showMenu.toggle() } }) {
            Image(systemName: "line.3.horizontal")
              .font(.system(size: 22, weight: .semibold))
              .foregroundColor(.white)
              .frame(width: size, height: size)
              .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String.loc("menu_accessibility_label"))
        }
      }
      .shadow(color: AppColors.shadowCard.opacity(0.6), radius: 8, x: 0, y: 4)
  .position(x: geo.size.width - padding - size/2,
                y: geo.size.height - padding - size/2)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      .zIndex(OverlayZIndex.menu)
    }
  }
}
