import SwiftUI

struct NetworkPermissionIntroOverlay: View {
  let onContinue: () -> Void
  let onLater: () -> Void
  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: { onLater() }).ignoresSafeArea()
      VStack(spacing: 22) {
        Text(String.loc("net_intro_title"))
          .appTitle()
          .multilineTextAlignment(.center)
          .foregroundColor(AppColors.textPrimary)
        Text(String.loc("net_intro_message"))
          .appBody()
          .foregroundColor(AppColors.textSecondary)
          .multilineTextAlignment(.leading)
        VStack(spacing: 14) {
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
              .foregroundColor(AppColors.highlightLight)
            Text(String.loc("net_intro_point_discovery"))
              .appCaption()
              .foregroundColor(AppColors.textSecondary)
              .multilineTextAlignment(.leading)
          }
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.open")
              .foregroundColor(AppColors.highlightLight)
            Text(String.loc("net_intro_point_privacy"))
              .appCaption()
              .foregroundColor(AppColors.textSecondary)
              .multilineTextAlignment(.leading)
          }
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "gearshape")
              .foregroundColor(AppColors.highlightLight)
            Text(String.loc("net_intro_point_change_later"))
              .appCaption()
              .foregroundColor(AppColors.textSecondary)
              .multilineTextAlignment(.leading)
          }
        }
        HStack(spacing: 12) {
          Button(String.loc("net_intro_not_now")) { onLater() }
            .buttonStyle(.modal(role: .secondary))
          Button(String.loc("net_intro_continue")) { onContinue() }
            .buttonStyle(.modal(role: .primary))
        }
      }
      .frame(maxWidth: 460)
      .padding(.horizontal, 24)
      .padding(.vertical, 32)
  .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AppColors.buttonListStroke, lineWidth: 1))
      .shadow(radius: 30, y: 12)
      .transition(.scale.combined(with: .opacity))
      .accessibilityElement(children: .combine)
    }
  }
}

#if DEBUG
struct NetworkPermissionIntroOverlay_Previews: PreviewProvider {
  static var previews: some View {
    ZStack {
      Color.black
      NetworkPermissionIntroOverlay(onContinue: {}, onLater: {})
    }.preferredColorScheme(.dark)
  }
}
#endif
