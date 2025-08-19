//
//  GameScreen.swift
//
//  Encapsulates the main chess game UI previously in ContentView.
//

import SwiftUI

private struct CaptureContext {
  let whiteCaptures: [Piece]
  let blackCaptures: [Piece]
  let lastCapturePieceID: UUID?
  let lastCapturingSide: PieceColor?
}

struct GameScreen: View {
  @ObservedObject var vm: GameViewModel
  // Local UI state
  @State private var selected: Square? = nil
  @State private var showPeerChooser = false
  @State private var selectedPeerToJoin: String? = nil
  @State private var exportFlash: Bool = false
  @State private var showHistorySlider: Bool = false
  @State private var historySliderOwner: PieceColor? = nil
  @State private var historyAnimationToken: Int = 0
  @State private var showMenu: Bool = false
  @State private var showLoadGame: Bool = false
  @State private var showNameEditor: Bool = false // new

  // MARK: Derived menu state
  private var menuState: GameMenuView.State {
    GameMenuView.State(
      movesMade: vm.movesMade,
      isConnected: vm.peers.isConnected,
      myColorIsWhite: vm.myColor.map { $0 == .white },
      canSwapColorsPreGame: vm.peers.isConnected && vm.movesMade == 0 && vm.myColor == .some(.white),
  hasPeersToJoin: !vm.peers.isConnected && !vm.allBrowsedPeerFriendlyNames.isEmpty,
  // Use friendly advertised / chosen player names if available (already de-duplicated upstream)
  browsedPeerNames: vm.allBrowsedPeerFriendlyNames,
  playerName: vm.playerName, // new
  needsNetworkingApproval: vm.needsNetworkingApproval, // new
  networkPermissionFixAvailable: (!vm.needsNetworkingApproval && vm.localNetworkPermissionLikelyDenied) // new
    )
  }
  private var menuAvailability: GameMenuButtonOverlay.Availability {
    var a: GameMenuButtonOverlay.Availability = []
    if vm.movesMade > 0 { a.insert(.newGame) }
    if !vm.peers.isConnected { a.insert(.rotate) }
    if vm.peers.isConnected && vm.movesMade == 0 && vm.myColor == .some(.white) { a.insert(.swap) }
  if !vm.peers.isConnected && !vm.allBrowsedPeerFriendlyNames.isEmpty { a.insert(.join) }
    return a
  }

  // MARK: Perspective helpers
  private var currentPerspective: PieceColor { vm.peers.isConnected ? (vm.myColor ?? .white) : vm.preferredPerspective }
  private var bottomSide: PieceColor { currentPerspective }
  private var topSide: PieceColor { vm.peers.isConnected ? (currentPerspective == .white ? .black : .white) : currentPerspective.opposite }

  var body: some View {
    ZStack {
      Color.clear
      viewBackground.ignoresSafeArea().highPriorityGesture(exportGesture)
      boardSection
  CombinedFloatingButtons(vm: vm, availability: menuAvailability, showMenu: $showMenu) { hideHistory() }
      if showMenu { GameMenuView(state: menuState, isPresented: $showMenu, showLoadGame: $showLoadGame, send: handleMenuAction) }
      GameScreenOverlays(
        vm: vm,
        showPeerChooser: $showPeerChooser,
        selectedPeerToJoin: $selectedPeerToJoin,
        showLoadGame: $showLoadGame,
        showNameEditor: $showNameEditor, // new
        onCancelPromotion: { vm.cancelPromotion() },
        onSelectPromotion: { vm.promote(to: $0) },
        onSelectPeer: { name in
          selectedPeerToJoin = name
          vm.confirmJoin(peerName: name)
          withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showPeerChooser = false }
        },
        onDismissPeerChooser: { withAnimation(.easeInOut(duration: 0.25)) { showPeerChooser = false } }
      )
      if exportFlash { exportFlashView }
    }
  // Keep the playing surface stable when keyboard appears for overlays (name entry, etc.)
  .ignoresSafeArea(.keyboard, edges: .bottom)
    .modifier(StateChangeHandlers(vm: vm,
                                  showPeerChooser: $showPeerChooser,
                                  showHistorySlider: $showHistorySlider,
                                  showMenu: $showMenu,
                                  hideHistory: hideHistory))
    // React to remote-driven history view sync (enter/exit)
    .onChange(of: vm.remoteIsDrivingHistoryView) { remoteDriving in
      if remoteDriving {
        // Show slider if remote entered history view and we aren't already showing
        if !showHistorySlider, vm.historyIndex != nil {
          historySliderOwner = vm.peers.isConnected ? vm.myColor : bottomSide
          withAnimation(.easeInOut(duration: 0.25)) { showHistorySlider = true }
        }
      } else {
        // Remote exited; hide if we were only in due to remote (i.e., user not interacting locally)
        if showHistorySlider, vm.historyIndex == nil {
          withAnimation(.easeInOut(duration: 0.25)) { showHistorySlider = false }
          historySliderOwner = nil
        }
      }
    }
    // Hide history slider when a revert is applied (confirmed) so all devices return to live mode
    .onChange(of: vm.lastAppliedHistoryRevertTarget) { _ in
      if showHistorySlider {
        withAnimation(.easeInOut(duration: 0.25)) { hideHistory() }
      }
    }
    .alert(String.loc("incoming_join_title"), isPresented: Binding<Bool>(get: { vm.incomingJoinRequestPeer != nil }, set: { if !$0 { vm.incomingJoinRequestPeer = nil } })) {
      Button(String.loc("yes")) { vm.respondToIncomingInvitation(true) }
      Button(String.loc("no"), role: .cancel) { vm.respondToIncomingInvitation(false) }
    } message: { Text(String.loc("incoming_join_message", vm.incomingJoinRequestPeer ?? "")) }
  }

  // MARK: Export gesture
  private var exportGesture: some Gesture {
    TapGesture(count: 5).onEnded {
      let text = vm.exportText()
#if canImport(UIKit)
      UIPasteboard.general.string = text
#endif
      withAnimation(.easeInOut(duration: 0.3)) { exportFlash = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        withAnimation(.easeOut(duration: 0.3)) { exportFlash = false }
      }
    }
  }

  private var exportFlashView: some View {
    Text("Copied state")
      .padding(8)
      .background(Color.black.opacity(0.7))
      .foregroundColor(.white)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .transition(.opacity)
      .zIndex(OverlayZIndex.exportFlash)
  }

  // MARK: Capture context
  private func captureContext() -> CaptureContext {
    if let idx = vm.historyIndex { // history reconstruction based on baseline FEN (avoids phantom captures)
      let recon = vm.captureReconstruction(at: idx)
      return CaptureContext(whiteCaptures: recon.whiteCaptures,
                            blackCaptures: recon.blackCaptures,
                            lastCapturePieceID: recon.lastCapturePieceID,
                            lastCapturingSide: recon.lastCapturingSide)
    }
    if let my = vm.myColor { // connected
      let whiteCaps = (my == .white) ? vm.capturedByMe : vm.capturedByOpponent
      let blackCaps = (my == .black) ? vm.capturedByMe : vm.capturedByOpponent
      return CaptureContext(whiteCaptures: whiteCaps, blackCaptures: blackCaps, lastCapturePieceID: vm.lastCapturedPieceID, lastCapturingSide: (vm.lastCaptureByMe == true ? my : my.opposite))
    } else { // single device
      let whiteCaps = vm.capturedByMe
      let blackCaps = vm.capturedByOpponent
      let lastSide: PieceColor? = {
        guard vm.lastCapturedPieceID != nil else { return nil }
        return (vm.lastCaptureByMe == true ? .white : .black)
      }()
      return CaptureContext(whiteCaptures: whiteCaps, blackCaptures: blackCaps, lastCapturePieceID: vm.lastCapturedPieceID, lastCapturingSide: lastSide)
    }
  }

  // MARK: History slider helpers
  private func hideHistory() {
    if vm.historyIndex != nil { stepHistoryToward(targetIndex: nil, animated: true) }
    showHistorySlider = false
    historySliderOwner = nil
  }
  private func stepHistoryToward(targetIndex: Int?, animated: Bool) {
    let current = vm.historyIndex ?? vm.moveHistory.count
    let target = targetIndex ?? vm.moveHistory.count
    if current == target { return }
    historyAnimationToken += 1
    let token = historyAnimationToken
    let distance = abs(target - current)
    let maxSteppedDistance = 20
    if !animated || distance > maxSteppedDistance {
      withAnimation(.easeInOut(duration: 0.35)) { vm.historyIndex = targetIndex }
      return
    }
    let stepDuration: Double = distance <= 8 ? 0.18 : 0.10
    let dir = target > current ? 1 : -1
    let indices: [Int] = stride(from: current + dir, through: target, by: dir).map { $0 }
    for (offset, idx) in indices.enumerated() {
      let delay = stepDuration * Double(offset)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak vm] in
        guard token == historyAnimationToken else { return }
        withAnimation(.easeInOut(duration: stepDuration)) { vm?.historyIndex = (idx == vm?.moveHistory.count ? nil : idx) }
      }
    }
  }

  // MARK: Turn status
  private func turnStatus(for overlayColor: PieceColor?) -> (text: String, color: Color)? {
    guard !vm.inHistoryView else { return nil }
    let currentSideToMove = vm.displayedSideToMove
    switch vm.displayedOutcomeForSide(overlayColor ?? currentSideToMove) {
    case .ongoing:
      let baseColor = currentSideToMove == .white ? String.loc("turn_white") : String.loc("turn_black")
      let showYou: Bool = {
        if vm.peers.isConnected {
          if let mine = vm.myColor, let ov = overlayColor, mine == ov, mine == currentSideToMove { return true }
          return false
        } else { if let ov = overlayColor, ov == currentSideToMove { return true }; return false }
      }()
      let colorText: String = {
        if showYou { return baseColor + " " + String.loc("you_mark") }
        // If this bar represents the opponent whose turn it is, append name in parentheses if available
        if vm.peers.isConnected, let mine = vm.myColor, let oppName = vm.opponentName, currentSideToMove != mine, overlayColor == currentSideToMove {
          return baseColor + " (" + oppName + ")"
        }
        return baseColor
      }()
      let fg = currentSideToMove == .white ? Color.white : Color.black
      return (String.loc("turn_prefix", colorText), fg)
    case .win: return (String.loc("win_text"), AppColors.highlightLight)
    case .loss: return (String.loc("loss_text"), AppColors.highlightLight)
    case .draw: return (String.loc("draw_text"), AppColors.highlightLight)
    }
  }

  // MARK: Background
  private var viewBackground: some View {
    ZStack {
      Color(red: 0.5, green: 0.5, blue: 0.5)
      let currentSideToMove = vm.displayedSideToMove
      if vm.displayedOutcomeForSide(currentSideToMove) == .ongoing {
        if vm.peers.isConnected {
          if let my = vm.myColor, currentSideToMove == my { AppColors.turnHighlight }
        } else {
          VStack(spacing: 0) {
            (currentSideToMove == topSide ? AppColors.turnHighlight : Color.clear).frame(maxHeight: .infinity)
            (currentSideToMove == bottomSide ? AppColors.turnHighlight : Color.clear).frame(maxHeight: .infinity)
          }.allowsHitTesting(false).transition(.opacity)
        }
      }
    }
  }

  let statusBarHeight: CGFloat = 50.0 // fixed height for status bar
  let capturedRowHeight: CGFloat = 50.0 // fixed height for captured row

  private var boardSection: some View {
    let ctx = captureContext()
    let material = materialDiff(on: vm.displayedBoard)
    let whiteLead = max(material, 0)
    let blackLead = max(-material, 0)
    let whiteCaps = ctx.whiteCaptures
    let blackCaps = ctx.blackCaptures
    let topPieces = topSide == .black ? blackCaps : whiteCaps
    let bottomPieces = bottomSide == .white ? whiteCaps : blackCaps

    return GeometryReader { geo in
      let dividerSize = 1.0
      // Compute available board size; prevent negative values when keyboard shrinks height (e.g. during text field editing overlays)
      let verticalChrome = 2.0 * (statusBarHeight + capturedRowHeight + dividerSize)
      let availableHeight = geo.size.height - verticalChrome
      let boardSize = max(0, min(geo.size.width, availableHeight))
      ZStack {
        viewBackground
        VStack(spacing: 0) {
          statusBar(for: topSide)
            .rotationEffect(!vm.peers.isConnected ? .degrees(180) : .degrees(0))
            .frame(height: statusBarHeight)
          capturedRow(for: topSide, pieces: topPieces, ctx: ctx, whiteLead: whiteLead, blackLead: blackLead, rotate: !vm.peers.isConnected)
            .padding(.horizontal, 5)
            .frame(height: capturedRowHeight)
          chessBoard.frame(width: boardSize, height: boardSize).overlay(
            Rectangle()
              .stroke(AppColors.boardBorder, lineWidth: dividerSize)
              .padding(-0.5 * dividerSize)
          ).padding(EdgeInsets(top: dividerSize, leading: 0, bottom: dividerSize, trailing: 0))
          capturedRow(for: bottomSide, pieces: bottomPieces, ctx: ctx, whiteLead: whiteLead, blackLead: blackLead, rotate: false)
            .padding(.horizontal, 5)
            .frame(height: capturedRowHeight)
          statusBar(for: bottomSide)
            .frame(height: statusBarHeight)
        }.frame(width: boardSize)
      }
    }
  }

  private func capturedRow(for side: PieceColor, pieces: [Piece], ctx: CaptureContext, whiteLead: Int, blackLead: Int, rotate: Bool) -> some View {
    let highlight: UUID? = {
      if vm.historyIndex != nil, let pid = ctx.lastCapturePieceID, let captSide = ctx.lastCapturingSide, captSide == side { return pid }
      if vm.historyIndex == nil {
        if (vm.lastCaptureByMe == true && side == (vm.myColor ?? .white)) || (vm.lastCaptureByMe == false && side == (vm.myColor?.opposite ?? .black)) { return vm.lastCapturedPieceID }
      }
      return nil
    }()
    let advantage = side == .white ? whiteLead : blackLead
    return CapturedRow(pieces: pieces, rotatePieces: rotate, highlightPieceID: highlight, pointAdvantage: advantage)
  }

  private var chessBoard: some View {
    let inCheck = vm.isDisplayedSideInCheck()
    let isMate = inCheck && vm.isDisplayedSideCheckmated()
    let displayedLastMove: Move? = {
      if let idx = vm.historyIndex { return (idx > 0 && idx <= vm.moveHistory.count) ? vm.moveHistory[idx - 1] : nil }
      return vm.lastMove
    }()
    return BoardView(
      board: vm.displayedBoard,
      perspective: vm.peers.isConnected ? (vm.myColor ?? .white) : vm.preferredPerspective,
      myColor: vm.myColor ?? (vm.preferredPerspective),
      sideToMove: vm.displayedSideToMove,
      inCheckCurrentSide: inCheck,
      isCheckmatePosition: isMate,
      singleDevice: !vm.peers.isConnected,
      lastMove: displayedLastMove,
      historyIndex: vm.historyIndex,
      disableInteraction: showHistorySlider || vm.historyIndex != nil,
      onAttemptInteraction: { hideHistory() },
      selected: $selected
    ) { from, to, single in
      if vm.historyIndex != nil { stepHistoryToward(targetIndex: nil, animated: true); return false }
      let success = single ? vm.makeLocalMove(from: from, to: to) : vm.makeMove(from: from, to: to)
      if success { hideHistory() }
      return success
    } legalMovesProvider: { origin in vm.legalDestinations(from: origin) }
      .onChange(of: vm.engine.sideToMove) { newValue in if let mine = vm.myColor, mine != newValue { selected = nil } }
      .onChange(of: vm.historyIndex) { newVal in if newVal != nil { withAnimation(.easeInOut(duration: 0.15)) { selected = nil } } }
      .aspectRatio(1, contentMode: .fit)
  }

  private func materialDiff(on board: Board) -> Int {
    var w = 0, b = 0
  for rank in 0..<8 { for file in 0..<8 { let sq = Square(file: file, rank: rank); if let p = board.piece(at: sq) { let v = GameViewModel.materialValue(p); if p.color == .white { w += v } else { b += v } } } }
    return w - b
  }

  // Overlays moved to GameScreenOverlays

  // MARK: Status bar with history slider
  private func statusBar(for overlayColor: PieceColor?) -> some View {
    let canShowSlider = vm.moveHistory.count > 0
    return ZStack {
      let showForThisBar: Bool = {
        if !showHistorySlider || !canShowSlider { return false }
        if vm.peers.isConnected { if let my = vm.myColor, overlayColor == my { return true }; return false }
        return overlayColor == historySliderOwner
      }()
      if showForThisBar {
        HistorySliderView(currentIndex: vm.historyIndex, totalMoves: vm.moveHistory.count) { newHistory in
          let current = vm.historyIndex ?? vm.moveHistory.count
          let dist = abs((newHistory ?? vm.moveHistory.count) - current)
          stepHistoryToward(targetIndex: newHistory, animated: dist <= 4)
        }
      } else if let status = turnStatus(for: overlayColor) {
        Text(status.text).font(.title).foregroundStyle(status.color)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { toggleHistory(for: overlayColor, canShowSlider: canShowSlider) }
  }
  private func toggleHistory(for overlayColor: PieceColor?, canShowSlider: Bool) {
    guard canShowSlider else { return }
    if vm.peers.isConnected {
      if showHistorySlider { hideHistory() } else { historySliderOwner = overlayColor; showHistorySlider = true }
    } else {
      if showHistorySlider { if historySliderOwner == overlayColor { hideHistory() } else { historySliderOwner = overlayColor } } else { historySliderOwner = overlayColor; showHistorySlider = true }
    }
  }

  // MARK: Menu actions
  private func handleMenuAction(_ action: GameMenuView.Action) {
    switch action {
    case .close: break
    case .newGameOrReset:
      if vm.peers.isConnected { hideHistory(); vm.resetGame() } else { vm.offlineResetPrompt = true }
    case .rotateBoard:
      withAnimation(.none) { vm.preferredPerspective = vm.preferredPerspective.opposite }
    case .swapColors:
      vm.swapColorsIfAllowed()
    case .loadGame:
      showLoadGame = true
    case .joinPeer(let name):
      vm.confirmJoin(peerName: name)
    case .showHistory:
      // Activate history slider for current bottom side (or my color when connected)
      if vm.moveHistory.count > 0 {
        let owner = vm.peers.isConnected ? vm.myColor : bottomSide
        historySliderOwner = owner
        withAnimation(.easeInOut(duration: 0.25)) { showHistorySlider = true }
      }
    case .changeName:
      showNameEditor = true
    case .enableNetworking:
      vm.requestNetworkingApproval()
    case .openLocalNetworkSettings:
      // Show explanatory overlay; user can then deep link to settings.
      vm.showLocalNetworkPermissionHelp = true
    }
  }
}

// MARK: State change side-effects factored as a ViewModifier
private struct StateChangeHandlers: ViewModifier {
  @ObservedObject var vm: GameViewModel
  @Binding var showPeerChooser: Bool
  @Binding var showHistorySlider: Bool
  @Binding var showMenu: Bool
  let hideHistory: () -> Void

  func body(content: Content) -> some View {
    content
      .onChange(of: vm.discoveredPeerNames) { new in
        if new.isEmpty { if showPeerChooser { showPeerChooser = false } } else if vm.otherDeviceNames.isEmpty { showPeerChooser = true }
      }
      .onChange(of: vm.moveHistory.count) { newCount in if newCount == 0 { hideHistory() } }
      .onChange(of: vm.engine.sideToMove) { newSide in
        if vm.peers.isConnected { if let mine = vm.myColor, newSide == mine { if showHistorySlider { hideHistory() } } }
        if vm.historyIndex == nil { announceTurnAndState(for: newSide) }
      }
      .onChange(of: vm.peers.isConnected) { connected in if connected, showMenu { withAnimation(.easeInOut(duration: 0.25)) { showMenu = false } } }
      .onChange(of: vm.showingPromotionPicker) { showing in
        guard vm.historyIndex == nil else { return }
        if showing { AccessibilityAnnouncer.announce(String.loc("announce_promotion_open")) }
        else if vm.pendingPromotionMove == nil { AccessibilityAnnouncer.announce(String.loc("announce_promotion_cancel")) }
      }
  }

  private func announceTurnAndState(for newSide: PieceColor) {
    AccessibilityAnnouncer.postTurnChange(for: newSide, myColor: vm.myColor, connected: vm.peers.isConnected)
    let side = newSide
    let inCheck = vm.engine.isInCheck(side)
    let isMate = vm.engine.isCheckmate(for: side)
    let isStale = vm.engine.isStalemate(for: side)
    if isMate {
      let key = (side == .white) ? "announce_checkmate_white" : "announce_checkmate_black"
      AccessibilityAnnouncer.announce(String.loc(key))
    } else if isStale {
      AccessibilityAnnouncer.announce(String.loc("announce_stalemate"))
    } else if inCheck {
      let key = (side == .white) ? "announce_check_white" : "announce_check_black"
      AccessibilityAnnouncer.announce(String.loc(key))
    }
  }
}

// MARK: Piece values (UI-level)
// (Removed local pieceValue in favor of GameViewModel.materialValue)

private func symbol(for p: Piece) -> String {
  switch p.type {
  case .king:   return "♚"
  case .queen:  return "♛"
  case .rook:   return "♜"
  case .bishop: return "♝"
  case .knight: return "♞"
  case .pawn:   return "♟︎"
  }
}
