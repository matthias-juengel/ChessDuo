import SwiftUI

struct NewGameConfirmOverlay: View {
  let message: String
  let destructiveTitle: String
  let keepTitle: String
  let onConfirm: () -> Void
  let onCancel: () -> Void

  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: onCancel)
      ModalCard {
        VStack(spacing: 20) {
          Text(String.loc("offline_new_game_title"))
            .font(.title2).bold()
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
          Text(message)
            .font(.body)
            .foregroundColor(.white.opacity(0.85))
            .multilineTextAlignment(.center)
          HStack(spacing: 14) {
            Button(keepTitle) { onCancel() }
              .buttonStyle(.modal(role: .secondary))
            Button(destructiveTitle) { onConfirm() }
              .buttonStyle(.modal(role: .destructive))
          }
        }
      }
      .modalTransition(animatedWith: true)
    }
  }
}

#if DEBUG
struct NewGameConfirmOverlay_Previews: PreviewProvider {
  static var previews: some View {
    NewGameConfirmOverlay(
      message: "This will end the current game.",
      destructiveTitle: "New Game",
      keepTitle: "Keep Playing",
      onConfirm: {},
      onCancel: {})
  }
}
#endif
