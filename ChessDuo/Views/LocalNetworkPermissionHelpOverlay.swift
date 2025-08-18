import SwiftUI

struct LocalNetworkPermissionHelpOverlay: View {
  let onOpenSettings: () -> Void
  let onDismiss: () -> Void
  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: { onDismiss() }).ignoresSafeArea()
      VStack(spacing: 20) {
        Text(String.loc("ln_help_title"))
          .appTitle()
          .multilineTextAlignment(.center)
          .foregroundColor(AppColors.textPrimary)
  Text(String.loc("ln_help_message", AppInfo.displayName))
          .appBody()
          .foregroundColor(AppColors.textSecondary)
          .multilineTextAlignment(.leading)
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "1.circle")
              .foregroundColor(AppColors.highlightLight)
            Text(String.loc("ln_help_step_settings"))
              .appCaption()
              .foregroundColor(AppColors.textSecondary)
          }
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "2.circle")
              .foregroundColor(AppColors.highlightLight)
            Text(String.loc("ln_help_step_toggle", AppInfo.displayName))
              .appCaption()
              .foregroundColor(AppColors.textSecondary)
          }
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "3.circle")
              .foregroundColor(AppColors.highlightLight)
            Text(String.loc("ln_help_step_return"))
              .appCaption()
              .foregroundColor(AppColors.textSecondary)
          }
        }
        HStack(spacing: 12) {
          Button(String.loc("ln_help_dismiss")) { onDismiss() }
            .buttonStyle(.modal(role: .secondary))
          Button(String.loc("ln_help_open")) { onOpenSettings() }
            .buttonStyle(.modal(role: .primary))
        }
      }
      .frame(maxWidth: 480)
      .padding(.horizontal, 24)
      .padding(.vertical, 32)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AppColors.buttonListStroke, lineWidth: 1))
      .shadow(radius: 30, y: 12)
      .transition(.scale.combined(with: .opacity))
    }
  }
}

#if DEBUG
struct LocalNetworkPermissionHelpOverlay_Previews: PreviewProvider {
  static var previews: some View {
    ZStack {
      Color.black
      LocalNetworkPermissionHelpOverlay(onOpenSettings: {}, onDismiss: {})
    }.preferredColorScheme(.dark)
  }
}
#endif
