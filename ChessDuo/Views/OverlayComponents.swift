import SwiftUI

// Central z-index constants (additional values can be added elsewhere as needed)
struct OverlayZIndex {
  static let menu: Double = 430 // below peer chooser (450) but above board content
  static let peerChooser: Double = 450
  static let promotion: Double = 500
  static let newGameConfirm: Double = 550
  static let exportFlash: Double = 900
  static let resetConnected: Double = 520
}

// Reusable semi-transparent full-screen backdrop.
struct OverlayBackdrop: View {
  let onTap: (() -> Void)?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var visible = false
  var body: some View {
    AppColors.backdrop
      .opacity(visible ? 1 : 0)
      .ignoresSafeArea()
      .contentShape(Rectangle())
      .onTapGesture { onTap?() }
      .accessibilityHidden(true)
      .onAppear {
        if reduceMotion {
          visible = true
        } else {
          withAnimation(.easeIn(duration: 0.18)) { visible = true }
        }
      }
  }
}

// Reusable modal card container with consistent styling.
struct ModalCard<Content: View>: View {
  var maxWidth: CGFloat = 420
  var padding: CGFloat = 24
  @ViewBuilder let content: Content
  var body: some View {
    content
      .padding(padding)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  .shadow(color: AppColors.shadowCard, radius: 14, x: 0, y: 6)
      .frame(maxWidth: maxWidth)
  }
}

private struct ModalTransitionModifier: ViewModifier {
  let trigger: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func body(content: Content) -> some View {
    if reduceMotion {
      content
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: trigger)
    } else {
      content
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: trigger)
    }
  }
}

extension View {
  // Reduce-motion aware convenience modal transition
  func modalTransition(animatedWith trigger: Bool) -> some View {
    modifier(ModalTransitionModifier(trigger: trigger))
  }
}

// MARK: - Modal Action Button Style

enum ModalButtonRole { case primary, secondary, destructive }

enum ModalButtonSize { case regular, compact }

struct ModalActionButtonStyle: ButtonStyle {
  var role: ModalButtonRole
  var size: ModalButtonSize = .regular
  func makeBody(configuration: Configuration) -> some View {
    let bg: Color
    let fg: Color
    switch role {
    case .primary:
  bg = AppColors.buttonPrimaryBG
      fg = .black
    case .secondary:
  bg = AppColors.buttonSecondaryBG
      fg = .white
    case .destructive:
  bg = AppColors.buttonDestructiveBG
      fg = .white
    }
    let hPad: CGFloat = (size == .regular) ? 18 : 10
    let vPad: CGFloat = (size == .regular) ? 10 : 6
    let corner: CGFloat = (size == .regular) ? 14 : 10
    let font: Font = (size == .regular) ? .title3 : .callout.weight(.semibold)
    return configuration.label
      .font(font)
      .padding(.horizontal, hPad)
      .padding(.vertical, vPad)
      .background(bg)
      .foregroundColor(fg)
      .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(AppColors.pieceWhite.opacity(role == .secondary ? 0.35 : 0.0), lineWidth: 1)
      )
  .fixedSize(horizontal: true, vertical: false) // avoid multi-line wrap
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == ModalActionButtonStyle {
  static func modal(role: ModalButtonRole, size: ModalButtonSize = .regular) -> ModalActionButtonStyle { ModalActionButtonStyle(role: role, size: size) }
}

extension View { func modalButton(role: ModalButtonRole, size: ModalButtonSize = .regular) -> some View { buttonStyle(.modal(role: role, size: size)) } }
