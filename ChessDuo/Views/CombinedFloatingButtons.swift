import SwiftUI

/// Shows the menu button in normal play; in history view shows a revert button with text and a close (X) to exit history.
struct CombinedFloatingButtons: View {
  @ObservedObject var vm: GameViewModel
  let availability: GameMenuButtonOverlay.Availability
  @Binding var showMenu: Bool
  let onHideHistory: () -> Void
  let size: CGFloat = 46
  let padding: CGFloat = 14

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.clear
      HStack(spacing: 12) {
        // History navigation buttons (view-only undo/redo) positioned leftmost when available.
        if vm.canUndoView || vm.canRedoView {
          undoRedoButtons
        }
        Spacer().background(deltaView)
        if let idx = vm.historyIndex { // History mode buttons
          historyModeButtons(idx)
        } else if availability.isEmpty == false { // Normal menu button only when NOT in history mode
          menuButton
        }
      }
      .shadow(color: AppColors.shadowCard.opacity(0.6), radius: 8, x: 0, y: 4)
      .frame(height: size)
      .padding(padding)
      .zIndex(OverlayZIndex.menu)
    }
  }

  @ViewBuilder
  private var deltaView: some View {
    // Display number of moves stepped back (negative delta) when in history view.
    if let idx = vm.historyIndex, vm.movesMade > idx {
      let delta = vm.movesMade - idx
      let deltaKey = delta == 1 ? "history_delta_badge_accessibility_one" : "history_delta_badge_accessibility_other"
       Text("-\(delta)")
         .font(.system(size: 15, weight: .semibold))
         .foregroundColor(.white)
         .frame(minWidth: 34)
         .accessibilityLabel(String.loc(deltaKey, String(delta)))
    }
  }

  @ViewBuilder
  private var undoRedoButtons: some View {
    // If neither undo nor redo is possible, show nothing (this view won't be called in that case upstream).
    // Always render the undo button when this block is shown; disable & dim if it cannot act.
    let undoEnabled = vm.canUndoView
    Button(action: {
      guard undoEnabled else { return }
      withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { vm.viewHistoryBack() }
    }) {
      Image(systemName: "chevron.left")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.white)
        .frame(width: size, height: size)
        .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
        .opacity(undoEnabled ? 1.0 : 0.35)
    }
    .buttonStyle(.plain)
    .disabled(!undoEnabled)
    .accessibilityLabel(String.loc("history_undo_button"))
    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
      guard undoEnabled else { return }
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { vm.jumpToHistoryStart() }
    })

    if vm.canRedoView {
      Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { vm.viewHistoryForward() } }) {
        Image(systemName: "chevron.right")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.white)
          .frame(width: size, height: size)
          .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String.loc("history_redo_button"))
      .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { vm.jumpToLiveState() }
      })
    }

  }

  @ViewBuilder
  private func historyModeButtons(_ idx: Int) -> some View {
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
  }

  @ViewBuilder
  private var menuButton: some View {
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
