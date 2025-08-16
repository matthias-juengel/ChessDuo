import SwiftUI

// Overlay shown when I requested a reset and I'm waiting for opponent to respond.
struct AwaitingResetOverlay: View {
  let cancelTitle: String
  let message: String
  let onCancel: () -> Void
  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: onCancel)
      ModalCard {
        VStack(spacing: 18) {
          Text(String.loc("awaiting_confirmation_title"))
            .appTitle()
            .multilineTextAlignment(.center)
            .foregroundColor(AppColors.textPrimary)
          Text(message)
            .appBody()
            .foregroundColor(AppColors.textSecondary)
            .multilineTextAlignment(.center)
          Button(cancelTitle) {
            Haptics.trigger(.resetDecline)
            onCancel()
          }
            .buttonStyle(.modal(role: .primary))
        }
      }
      .modalTransition(animatedWith: true)
    }
    .zIndex(OverlayZIndex.resetConnected)
  }
}

// Overlay shown when opponent requested a reset.
struct IncomingResetRequestOverlay: View {
  let message: String
  let acceptTitle: String
  let declineTitle: String
  let onAccept: () -> Void
  let onDecline: () -> Void
  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: onDecline)
      ModalCard {
        VStack(spacing: 18) {
          Text(String.loc("reset_accept_title"))
            .appTitle()
            .multilineTextAlignment(.center)
            .foregroundColor(AppColors.textPrimary)
          Text(message)
            .appBody()
            .foregroundColor(AppColors.textSecondary)
            .multilineTextAlignment(.center)
          HStack(spacing: 14) {
            Button(declineTitle) {
              Haptics.trigger(.resetDecline)
              onDecline()
            }
              .buttonStyle(.modal(role: .secondary))
            Button(acceptTitle) {
              Haptics.trigger(.resetAccept)
              onAccept()
            }
              .buttonStyle(.modal(role: .destructive))
          }
        }
      }
      .modalTransition(animatedWith: true)
    }
  .onAppear { Haptics.trigger(.resetRequestIncoming) }
    .zIndex(OverlayZIndex.resetConnected)
  }
}

#if DEBUG
struct ResetOverlays_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      AwaitingResetOverlay(
        cancelTitle: "Cancel",
        message: "Reset request sent...",
        onCancel: {}
      )
      IncomingResetRequestOverlay(
        message: "Opponent wants to reset the game.",
        acceptTitle: "Yes",
        declineTitle: "No",
        onAccept: {},
        onDecline: {}
      )
    }
    .preferredColorScheme(.dark)
  }
}
#endif
