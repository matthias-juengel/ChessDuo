import SwiftUI

struct PeerJoinOverlayView: View {
  let peers: [String]
  let selected: String?
  let onSelect: (String) -> Void
  let onCancel: () -> Void

  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: onCancel)
      ModalCard {
        VStack(spacing: 16) {
          Text(String.loc("found_devices_section"))
            .font(.title2).bold()
            .foregroundColor(.white)
          Text(String.loc("peer_join_subtitle"))
            .font(.callout)
            .foregroundColor(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)

        if peers.isEmpty {
          Text(String.loc("no_devices_found"))
            .foregroundColor(.white.opacity(0.8))
            .padding(.vertical, 20)
        } else {
          ScrollView {
            VStack(spacing: 10) {
              ForEach(peers, id: \.self) { name in
                Button(action: { onSelect(name) }) {
                  HStack {
                    Text(name)
                      .font(.title3)
                      .foregroundColor(.white)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    if selected == name { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                  }
                  .padding(.horizontal, 14)
                  .padding(.vertical, 10)
                  .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                  .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
              }
            }
            .padding(.vertical, 4)
          }
          .frame(maxHeight: 260)
        }

          HStack(spacing: 12) {
            Button(String.loc("cancel")) { onCancel() }
              .buttonStyle(.modal(role: .primary))
              .accessibilityLabel(String.loc("cancel"))
          }
        }
      }
      .modalTransition(animatedWith: (peers.count != 0))
    }
  }
}

#if DEBUG
struct PeerJoinOverlayView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      PeerJoinOverlayView(peers: ["iPad", "iPhone 15", "MacBook Pro"], selected: "iPhone 15", onSelect: { _ in }, onCancel: {})
      PeerJoinOverlayView(peers: [], selected: nil, onSelect: { _ in }, onCancel: {})
    }
  }
}
#endif
