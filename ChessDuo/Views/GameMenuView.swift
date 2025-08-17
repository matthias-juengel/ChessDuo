//
//  GameMenuView.swift
//  ChessDuo
//
//  A decoupled game menu component independent from ContentView & GameViewModel.
//  It receives a lightweight immutable State plus an action callback.
//

import SwiftUI

struct GameMenuView: View {
  struct State: Equatable {
    var movesMade: Int
    var isConnected: Bool
    var myColorIsWhite: Bool? // nil if unknown / single-device
    var canSwapColorsPreGame: Bool // derived externally
    var hasPeersToJoin: Bool
    var browsedPeerNames: [String]
  }

  enum Action: Equatable {
    case close
    case newGameOrReset
    case rotateBoard
    case swapColors
    case loadGame
    case joinPeer(String)
  case showHistory
  }

  let state: State
  @Binding var isPresented: Bool
  @Binding var showLoadGame: Bool
  let send: (Action) -> Void

  var body: some View {
    ZStack {
      OverlayBackdrop(onTap: { dismiss() })
        .zIndex(OverlayZIndex.menu)
      content
        .zIndex(OverlayZIndex.menu + 1)
        .modalTransition(animatedWith: isPresented)
    }
  }

  private func dismiss() { withAnimation(.easeInOut(duration: 0.25)) { isPresented = false; send(.close) } }

  private var content: some View {
    VStack(spacing: 0) {
      header
      ScrollView(showsIndicators: false) {
        VStack(spacing: 10) { entries }
          .padding(.bottom, 8)
      }
      .frame(maxHeight: 420)
      .padding(.horizontal, 4)
      .padding(.bottom, 8)
    }
    .padding(.horizontal, 18)
    .padding(.bottom, 18)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .shadow(color: AppColors.shadowCard, radius: 14, x: 0, y: 6)
    .padding(.horizontal, 28)
    .frame(maxWidth: 440)
  }

  private var header: some View {
    ZStack {
      Text(String.loc("menu_title"))
        .appTitle()
        .foregroundColor(AppColors.textPrimary)
        .frame(maxWidth: .infinity)
      HStack {
        Spacer()
        Button(action: { dismiss() }) {
          Image(systemName: "xmark")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String.loc("menu_close"))
      }
    }
    .padding(.horizontal, 6)
    .padding(.top, 14)
    .padding(.bottom, 8)
  }

  @ViewBuilder private var entries: some View {
    if state.movesMade > 0 { // New / Reset
      menuButton(icon: "flag.fill", text: String.loc("menu_new_game")) {
        dismiss()
        send(.newGameOrReset)
      }
    }
    menuButton(icon: "doc.text", text: String.loc("menu_load_game")) {
      dismiss()
      send(.loadGame)
    }.padding(.bottom, 20) // Only add padding if no new game
    if !state.isConnected { // Rotate
      menuButton(icon: "arrow.triangle.2.circlepath", text: String.loc("menu_rotate_board")) {
        dismiss()
        send(.rotateBoard)
      }
    }
    if state.canSwapColorsPreGame { // Swap colors
      menuButton(icon: "arrow.left.arrow.right", text: String.loc("menu_play_black")) {
        dismiss()
        send(.swapColors)
      }
    }
    if state.movesMade > 0 { // Show history
      menuButton(icon: "clock.arrow.circlepath", text: String.loc("menu_show_history")) {
        dismiss()
        send(.showHistory)
      }
    }
    if !state.isConnected, state.hasPeersToJoin {
      VStack(spacing: 6) {
        HStack {
          Text(String.loc("menu_join_section"))
            .font(.caption.weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
          Spacer(minLength: 0)
        }
        ForEach(state.browsedPeerNames, id: \.self) { peer in
          menuButton(icon: "person.2", text: peer) {
            dismiss()
            send(.joinPeer(peer))
          }
        }
      }
      .padding(.top, 4)
    }
  }

  private func menuButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(.white)
          .frame(width: 32, alignment: .center)
        Text(text)
          .font(.title3.weight(.semibold))
          .foregroundColor(AppColors.textPrimary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .frame(minHeight: 48)
      .background(AppColors.buttonListBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.buttonListStroke, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(text)
  }
}

// Floating trigger; same logic but independent.
struct GameMenuButtonOverlay: View {
  struct Availability: OptionSet { let rawValue: Int; static let newGame = Availability(rawValue: 1<<0); static let rotate = Availability(rawValue: 1<<1); static let swap = Availability(rawValue: 1<<2); static let join = Availability(rawValue: 1<<3) }

  let availability: Availability
  @Binding var isPresented: Bool

  var body: some View {
    GeometryReader { geo in
      if availability.isEmpty == false {
        let size: CGFloat = 46
        let padding: CGFloat = 14
        Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isPresented.toggle() } }) {
          Image(systemName: "line.3.horizontal")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(AppColors.buttonSymbolBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.buttonSymbolStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .shadow(color: AppColors.shadowCard.opacity(0.6), radius: 8, x: 0, y: 4)
        .position(x: geo.size.width - padding - size/2,
                  y: geo.size.height - padding - size/2)
        .zIndex(OverlayZIndex.menu)
        .accessibilityLabel(String.loc("menu_accessibility_label"))
      }
    }
    .allowsHitTesting(true)
  }
}

#if DEBUG
struct GameMenuView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      GameMenuView(
        state: .init(
          movesMade: 5,
          isConnected: false,
          myColorIsWhite: true,
          canSwapColorsPreGame: false,
          hasPeersToJoin: true,
          browsedPeerNames: ["iPad", "MacBook Pro"]
        ),
        isPresented: .constant(true),
        showLoadGame: .constant(false),
        send: { _ in }
      )
      .preferredColorScheme(.dark)

      GameMenuView(
        state: .init(
          movesMade: 0,
          isConnected: true,
          myColorIsWhite: true,
          canSwapColorsPreGame: true,
          hasPeersToJoin: false,
          browsedPeerNames: []
        ),
        isPresented: .constant(true),
        showLoadGame: .constant(false),
        send: { _ in }
      )
      .preferredColorScheme(.dark)
    }
  }
}
#endif
