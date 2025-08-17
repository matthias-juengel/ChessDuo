import SwiftUI

// Lightweight keyboard height reader so only the overlay shifts, not the underlying board layout.
private final class KeyboardObserver: ObservableObject {
  @Published var height: CGFloat = 0
  private var willShow: NSObjectProtocol?
  private var willHide: NSObjectProtocol?
  init() {
    willShow = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] note in
      guard let self else { return }
      if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
        // Avoid publishing inside the immediate view update transaction; dispatch async.
        DispatchQueue.main.async { self.height = frame.height }
      }
    }
    willHide = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self else { return }
      DispatchQueue.main.async { self.height = 0 }
    }
  }
  deinit {
    if let w = willShow { NotificationCenter.default.removeObserver(w) }
    if let w = willHide { NotificationCenter.default.removeObserver(w) }
  }
}

struct NameChangeOverlay: View {
  @State private var name: String
  @FocusState private var focusField: Bool
  @StateObject private var kb = KeyboardObserver()
  let isFirstLaunch: Bool
  let onSave: (String) -> Void
  let onLater: () -> Void

  init(initialName: String, isFirstLaunch: Bool, onSave: @escaping (String) -> Void, onLater: @escaping () -> Void) {
    _name = State(initialValue: initialName)
    self.isFirstLaunch = isFirstLaunch
    self.onSave = onSave
    self.onLater = onLater
  }

  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: { onLater() })
        .ignoresSafeArea()
      // Keep the card stable (no vertical travel) roughly in upper/middle portion regardless of keyboard.
      VStack {
        // Fixed small top spacer to pin the card in upper half (prevents keyboard overlap)
        Spacer().frame(height: 40)
        ModalCard {
          VStack(spacing: 18) {
          Text(isFirstLaunch ? String.loc("name_prompt_title_first") : String.loc("name_prompt_title"))
            .appTitle()
            .multilineTextAlignment(.center)
            .foregroundColor(AppColors.textPrimary)
          Text(isFirstLaunch ? String.loc("name_prompt_message_first") : String.loc("name_prompt_message"))
            .appBody()
            .foregroundColor(AppColors.textSecondary)
            .multilineTextAlignment(.center)
          VStack(spacing: 8) {
            TextField(String.loc("name_prompt_placeholder"), text: $name)
              .focused($focusField)
              .onChange(of: name) { newVal in
                // Limit length to avoid extreme layout sizes
                if newVal.count > 32 { name = String(newVal.prefix(32)) }
              }
              .textInputAutocapitalization(.words)
              .disableAutocorrection(true)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.buttonListBG))
              .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonListStroke, lineWidth: 1))
              .foregroundColor(AppColors.textPrimary)
          }
          HStack(spacing: 12) {
            Button(String.loc("name_prompt_later")) { onLater() }
              .buttonStyle(.modal(role: .secondary))
            Button(String.loc("name_prompt_save")) { let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines); if !trimmed.isEmpty { onSave(trimmed) } else { onLater() } }
              .buttonStyle(.modal(role: .primary))
          }
          }
        }
        .frame(maxWidth: 420) // keep a sensible width on large devices
  Spacer(minLength: 0)
      }
      .padding(.horizontal, 24)
      .transition(.scale.combined(with: .opacity))
      .modalTransition(animatedWith: true)
    }
    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focusField = true } }
  }
}

// Helper to fetch safe area bottom inset (so we only lift additional keyboard overlap beyond the inset)
// Retained for potential future use; currently not needed for fixed-position layout.
private func safeAreaBottom() -> CGFloat { 0 }

#if DEBUG
struct NameChangeOverlay_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      NameChangeOverlay(initialName: "iPhone", isFirstLaunch: true, onSave: { _ in }, onLater: {})
      NameChangeOverlay(initialName: "Alice", isFirstLaunch: false, onSave: { _ in }, onLater: {})
    }
    .preferredColorScheme(.dark)
  }
}
#endif
