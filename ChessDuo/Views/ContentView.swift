//
//  ContentView.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import SwiftUI

// Aggregated capture context used by the UI (live or historical)
private struct CaptureContext {
  let whiteCaptures: [Piece]
  let blackCaptures: [Piece]
  let lastCapturePieceID: UUID?
  let lastCapturingSide: PieceColor?
}

private extension ContentView {
  func captureContext() -> CaptureContext {
    // Historical reconstruction if needed
    if let idx = vm.historyIndex {
      var engine = ChessEngine()
      var capsByWhite: [Piece] = []
      var capsByBlack: [Piece] = []
      var lastCapID: UUID? = nil
      var capturingSide: PieceColor? = nil
      let upto = min(idx, vm.moveHistory.count)
      for i in 0..<upto {
        let move = vm.moveHistory[i]
        var capturedPiece: Piece? = nil
        if let piece = engine.board.piece(at: move.to) {
          capturedPiece = piece
        } else if let moving = engine.board.piece(at: move.from), moving.type == .pawn, move.from.file != move.to.file, engine.board.piece(at: move.to) == nil {
          let dir = moving.color == .white ? 1 : -1
            let capturedSq = Square(file: move.to.file, rank: move.to.rank - dir)
            if let epPawn = engine.board.piece(at: capturedSq), epPawn.color != moving.color, epPawn.type == .pawn { capturedPiece = epPawn }
        }
        if let cap = capturedPiece {
          if cap.color == .white { // black captured white piece
            capsByBlack.append(cap)
            lastCapID = cap.id
            capturingSide = .black
          } else {
            capsByWhite.append(cap)
            lastCapID = cap.id
            capturingSide = .white
          }
        }
        _ = engine.tryMakeMove(move)
      }
      return CaptureContext(whiteCaptures: capsByWhite, blackCaptures: capsByBlack, lastCapturePieceID: lastCapID, lastCapturingSide: capturingSide)
    }
    // Live context
    if let my = vm.myColor { // connected: adapt perspective lists to absolute colors
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
}

struct ContentView: View {
  @StateObject private var vm = GameViewModel()
  @State private var selected: Square? = nil
  @State private var showPeerChooser = false
  @State private var selectedPeerToJoin: String? = nil
  @State private var exportFlash: Bool = false
  @State private var showHistorySlider: Bool = false
  @State private var historySliderOwner: PieceColor? = nil // which side opened the slider (single-device)
  @State private var historyAnimationToken: Int = 0 // used to cancel in-flight history step animations
  @State private var showMenu: Bool = false
  @State private var showLoadGame: Bool = false

  // MARK: - Perspective Helpers
  // Current board orientation perspective (bottom side color). In connected mode this is my multiplayer color (if known) else white; in single-device it's the persisted preference.
  private var currentPerspective: PieceColor { vm.peers.isConnected ? (vm.myColor ?? .white) : vm.preferredPerspective }
  // Color shown at the bottom of the board for current orientation.
  private var bottomSide: PieceColor { currentPerspective }
  // Color shown at the top of the board (opposite of bottom; in connected mode always the other player's color). In single-device mode just the opposite of preferred orientation.
  private var topSide: PieceColor { vm.peers.isConnected ? (currentPerspective == .white ? .black : .white) : currentPerspective.opposite }

  // Centralized helper: hide slider AND ensure we're on latest game state
  private func hideHistory() {
    if vm.historyIndex != nil {
      // Animate stepping to live so pieces traverse their actual move path
      stepHistoryToward(targetIndex: nil, animated: true)
    }
    showHistorySlider = false
    historySliderOwner = nil
  }

  // Step history index gradually so each move animates its piece movement.
  // targetIndex: nil means live (moveHistory.count)
  private func stepHistoryToward(targetIndex: Int?, animated: Bool) {
    let current = vm.historyIndex ?? vm.moveHistory.count
    let target = targetIndex ?? vm.moveHistory.count
    if current == target { return }
    historyAnimationToken += 1
    let token = historyAnimationToken
    let distance = abs(target - current)
    // Threshold: if too large, avoid long animation. Above threshold, jump directly with single animation.
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
        guard token == historyAnimationToken else { return } // canceled
        withAnimation(.easeInOut(duration: stepDuration)) {
          vm?.historyIndex = (idx == vm?.moveHistory.count ? nil : idx)
        }
      }
    }
  }

  // Compute status text for a specific overlay perspective (overlayColor).
   private func turnStatus(for overlayColor: PieceColor?) -> (text: String, color: Color)? {
    // Don't show turn status when viewing historic positions
    guard !vm.inHistoryView else { return nil }
  // Debug print removed
    let currentSideToMove = vm.displayedSideToMove
    switch vm.displayedOutcomeForSide(overlayColor ?? currentSideToMove) {
    case .ongoing:
      let baseColor = currentSideToMove == .white ? String.loc("turn_white") : String.loc("turn_black")
      let showYou: Bool = {
        if vm.peers.isConnected {
          // Only my own overlay and only if I'm the side to move
          if let mine = vm.myColor, let ov = overlayColor, mine == ov, mine == currentSideToMove { return true }
          return false
        } else {
          // Single-device: only the overlay whose color is the side to move shows (you)
          if let ov = overlayColor, ov == currentSideToMove { return true }
          return false
        }
      }()
      let colorText = showYou ? baseColor + " " + String.loc("you_mark") : baseColor
      let fg = currentSideToMove == .white ? Color.white : Color.black
      return (String.loc("turn_prefix", colorText), fg)
    case .win: return (String.loc("win_text"), AppColors.highlightLight)
    case .loss: return (String.loc("loss_text"), AppColors.highlightLight)
    case .draw: return (String.loc("draw_text"), AppColors.highlightLight)
    }
  }

  var viewBackground: some View {
    // Full-screen background indicating turn status
    ZStack {
      Color(red: 0.5, green: 0.5, blue: 0.5)
      let currentSideToMove = vm.displayedSideToMove
      if vm.displayedOutcomeForSide(currentSideToMove) == .ongoing { // show turn background only while game running
        if vm.peers.isConnected {
          if let my = vm.myColor, currentSideToMove == my {
            AppColors.turnHighlight
          }
        } else {
          // Single-device: highlight only the half (top or bottom) whose color is to move.
          VStack(spacing: 0) {
            (currentSideToMove == topSide ? AppColors.turnHighlight : Color.clear)
              .frame(maxHeight: .infinity)
            (currentSideToMove == bottomSide ? AppColors.turnHighlight : Color.clear)
              .frame(maxHeight: .infinity)
          }
          .allowsHitTesting(false)
          .transition(.opacity)
        }
      }
    }
  }

  // MARK: - Board & Captured Rows
  private var boardSection: some View {
    let ctx = captureContext()
    let material = materialDiff(on: vm.displayedBoard)
    let whiteLead = max(material, 0)
    let blackLead = max(-material, 0)
    let whiteCaps = ctx.whiteCaptures
    let blackCaps = ctx.blackCaptures
    let topPieces = topSide == .black ? blackCaps : whiteCaps
    let bottomPieces = bottomSide == .white ? whiteCaps : blackCaps
    return VStack(spacing: 0) {
      // Top status bar
      statusBar(for: topSide)
        .rotationEffect(!vm.peers.isConnected ? .degrees(180) : .degrees(0))
        .padding(.top, 4)
      capturedRow(for: topSide, pieces: topPieces, ctx: ctx, whiteLead: whiteLead, blackLead: blackLead, rotate: !vm.peers.isConnected)
        .padding(.horizontal, 10).padding(.top, 4)
      Color.black.frame(height: 1)
      chessBoard
      Color.black.frame(height: 1)
      capturedRow(for: bottomSide, pieces: bottomPieces, ctx: ctx, whiteLead: whiteLead, blackLead: blackLead, rotate: false)
        .padding(.horizontal, 10).padding(.bottom, 4)
      // Bottom status bar
      statusBar(for: bottomSide)
        .padding(.bottom, 8)
    }
  }

  private func capturedRow(for side: PieceColor, pieces: [Piece], ctx: CaptureContext, whiteLead: Int, blackLead: Int, rotate: Bool) -> some View {
    let highlight: UUID? = {
      if vm.historyIndex != nil, let pid = ctx.lastCapturePieceID, let captSide = ctx.lastCapturingSide, captSide == side { return pid }
      if vm.historyIndex == nil {
        if (vm.lastCaptureByMe == true && side == (vm.myColor ?? .white)) || (vm.lastCaptureByMe == false && side == (vm.myColor?.opposite ?? .black)) {
          return vm.lastCapturedPieceID
        }
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
  }
  legalMovesProvider: { origin in vm.legalDestinations(from: origin) }
    .onChange(of: vm.engine.sideToMove) { newValue in
      if let mine = vm.myColor, mine != newValue { selected = nil }
    }
    .onChange(of: vm.historyIndex) { newVal in
      if newVal != nil { withAnimation(.easeInOut(duration: 0.15)) { selected = nil } }
    }
    .aspectRatio(1, contentMode: .fit)
  }

  private func materialDiff(on board: Board) -> Int {
    var w = 0, b = 0
    for rank in 0..<8 { for file in 0..<8 { let sq = Square(file: file, rank: rank); if let p = board.piece(at: sq) { let v = pieceValue(p); if p.color == .white { w += v } else { b += v } } } }
    return w - b
  }

  //        // Connected devices footer
  //        if !vm.otherDeviceNames.isEmpty {
  //          Text("Andere Geräte: " + vm.otherDeviceNames.joined(separator: ", "))
  //            .font(.caption2)
  //            .foregroundStyle(.secondary)
  //            .frame(maxWidth: .infinity, alignment: .center)
  //        } else {
  //          Text("Keine anderen Geräte verbunden")
  //            .font(.caption2)
  //            .foregroundStyle(.tertiary)
  //            .frame(maxWidth: .infinity, alignment: .center)
  //        }

  var body: some View {
    ZStack {
      viewBackground.ignoresSafeArea().highPriorityGesture(
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
      )

      boardSection.ignoresSafeArea()
        .contentShape(Rectangle())
        // Overlay controls removed; status bars integrated into boardSection
  // Hamburger button & menu layer
  GameMenuButtonOverlay(
    availability: menuAvailability,
    isPresented: $showMenu
  )
  if showMenu {
    GameMenuView(
      state: menuState,
      isPresented: $showMenu,
      showLoadGame: $showLoadGame,
      send: handleMenuAction
    )
  }
  promotionLayer
  newGameConfirmLayer
  loadGameLayer
  peerChooserLayer
  connectedResetLayers
  if exportFlash { Text("Copied state")
          .padding(8)
          .background(Color.black.opacity(0.7))
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .transition(.opacity)
          .zIndex(OverlayZIndex.exportFlash)
      }
    }
    .onChange(of: vm.discoveredPeerNames) { new in
      // Show chooser when a new peer appears and we're not connected; hide automatically if list empties while visible
      if new.isEmpty {
        if showPeerChooser { showPeerChooser = false }
      } else if vm.otherDeviceNames.isEmpty {
        showPeerChooser = true
      }
    }
    // Hide slider if history cleared (e.g., new game)
    .onChange(of: vm.moveHistory.count) { newCount in
  if newCount == 0 { hideHistory() }
    }
    // Hide slider when opponent makes a move (connected mode)
    .onChange(of: vm.engine.sideToMove) { newSide in
      if vm.peers.isConnected {
        if let mine = vm.myColor, newSide == mine { // opponent just moved
          if showHistorySlider { hideHistory() }
        }
      }
      // Accessibility announcement for turn changes (live game only, ignore when viewing history)
      if vm.historyIndex == nil {
        AccessibilityAnnouncer.postTurnChange(for: newSide, myColor: vm.myColor, connected: vm.peers.isConnected)
        // After announcing turn, also announce any check / end-of-game state for the side now to move or just moved.
        // Determine board outcome from perspective of side now to move.
        let side = newSide
        // Use engine directly (live state) for status.
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
    // Hide menu automatically if a connection becomes active (initiated from remote)
    .onChange(of: vm.peers.isConnected) { connected in
      if connected, showMenu { withAnimation(.easeInOut(duration: 0.25)) { showMenu = false } }
    }
    // Promotion picker open/close announcements
    .onChange(of: vm.showingPromotionPicker) { showing in
      guard vm.historyIndex == nil else { return } // ignore in history view
      if showing {
        AccessibilityAnnouncer.announce(String.loc("announce_promotion_open"))
      } else if vm.pendingPromotionMove == nil { // closed without choosing or after completion
        AccessibilityAnnouncer.announce(String.loc("announce_promotion_cancel"))
      }
    }
  // Connected reset alerts replaced by custom overlays (see connectedResetLayers)
  // Custom peer chooser overlay replaces sheet
    .alert(String.loc("incoming_join_title"), isPresented: Binding<Bool>(get: { vm.incomingJoinRequestPeer != nil }, set: { if !$0 { vm.incomingJoinRequestPeer = nil } })) {
      Button(String.loc("yes")) { vm.respondToIncomingInvitation(true) }
      Button(String.loc("no"), role: .cancel) { vm.respondToIncomingInvitation(false) }
    } message: {
      Text(String.loc("incoming_join_message", vm.incomingJoinRequestPeer ?? ""))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private extension ContentView {
  var menuState: GameMenuView.State {
    GameMenuView.State(
      movesMade: vm.movesMade,
      isConnected: vm.peers.isConnected,
      myColorIsWhite: vm.myColor.map { $0 == .white },
      canSwapColorsPreGame: vm.peers.isConnected && vm.movesMade == 0 && vm.myColor == .some(.white),
      hasPeersToJoin: !vm.peers.isConnected && !vm.allBrowsedPeerNames.isEmpty,
      browsedPeerNames: vm.allBrowsedPeerNames
    )
  }

  var menuAvailability: GameMenuButtonOverlay.Availability {
    var a: GameMenuButtonOverlay.Availability = []
    if vm.movesMade > 0 { a.insert(.newGame) }
    if !vm.peers.isConnected { a.insert(.rotate) }
    if vm.peers.isConnected && vm.movesMade == 0 && vm.myColor == .some(.white) { a.insert(.swap) }
    if !vm.peers.isConnected && !vm.allBrowsedPeerNames.isEmpty { a.insert(.join) }
    return a
  }

  func handleMenuAction(_ action: GameMenuView.Action) {
    switch action {
    case .close: break
    case .newGameOrReset:
      if vm.peers.isConnected {
        hideHistory()
        vm.resetGame()
      } else {
        vm.offlineResetPrompt = true
      }
    case .rotateBoard:
      withAnimation(.none) { vm.preferredPerspective = vm.preferredPerspective.opposite }
    case .swapColors:
      vm.swapColorsIfAllowed()
    case .loadGame:
      showLoadGame = true
    case .joinPeer(let name):
      vm.confirmJoin(peerName: name)
    }
  }
  // Dedicated overlay layer to isolate promotion picker transitions from the board layout.
  var promotionLayer: some View {
    ZStack { // Always present layer to avoid parent ZStack layout changes.
      if vm.showingPromotionPicker, let pending = vm.pendingPromotionMove {
        let promoColor = vm.engine.board.piece(at: pending.from)?.color ?? vm.engine.sideToMove.opposite
        let rotate = !vm.peers.isConnected && promoColor == .black
        ZStack {
          OverlayBackdrop(onTap: { vm.cancelPromotion() })
          ModalCard() {
            PromotionPickerView(color: promoColor, rotate180: rotate, onSelect: { vm.promote(to: $0) }, onCancel: { vm.cancelPromotion() })
          }
        }
        .modalTransition(animatedWith: vm.showingPromotionPicker)
  .zIndex(OverlayZIndex.promotion)
      }
    }
  }

  // Connected-mode reset overlays (incoming & awaiting) replacing system alerts.
  var connectedResetLayers: some View {
    ZStack {
      if vm.peers.isConnected { // Only relevant in connected mode
        if vm.incomingResetRequest {
          IncomingResetRequestOverlay(
            message: String.loc("opponent_requests_reset"),
            acceptTitle: String.loc("reset_accept_yes"),
            declineTitle: String.loc("reset_accept_no"),
            onAccept: { vm.respondToResetRequest(accept: true) },
            onDecline: { vm.respondToResetRequest(accept: false) }
          )
        }
        if vm.awaitingResetConfirmation {
          AwaitingResetOverlay(
            cancelTitle: String.loc("reset_cancel_request"),
            message: String.loc("reset_request_sent"),
            onCancel: { vm.respondToResetRequest(accept: false) }
          )
        }
      }
    }
  }

  var peerChooserLayer: some View {
    ZStack {
      if showPeerChooser {
        PeerJoinOverlayView(
          peers: vm.discoveredPeerNames,
          selected: selectedPeerToJoin,
          onSelect: { name in
            selectedPeerToJoin = name
            vm.confirmJoin(peerName: name)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showPeerChooser = false }
          },
          onCancel: {
            withAnimation(.easeInOut(duration: 0.25)) { showPeerChooser = false }
          },
          animated: true
        )
        .zIndex(OverlayZIndex.peerChooser)
        .transition(.opacity) // Backdrop fade handled internally; opacity pairs nicely with card scale
      }
    }
  }

  var newGameConfirmLayer: some View {
    ZStack {
      if vm.offlineResetPrompt { // Re-use existing state flag
        NewGameConfirmOverlay(
          message: String.loc("offline_new_game_message"),
          destructiveTitle: String.loc("offline_new_game_confirm"),
          keepTitle: String.loc("offline_new_game_keep"),
          onConfirm: { vm.performLocalReset(send: false) },
          onCancel: { vm.offlineResetPrompt = false }
        )
  .zIndex(OverlayZIndex.newGameConfirm)
        .modalTransition(animatedWith: vm.offlineResetPrompt)
      }
    }
  }

  var loadGameLayer: some View {
    ZStack {
      if showLoadGame {
        LoadGameOverlay(vm: vm, showLoadGame: $showLoadGame)
          .zIndex(OverlayZIndex.menu + 2)
      }
    }
  }
}

private extension ContentView {
  // overlayControls removed in favor of integrated status bars inside boardSection

  func statusBar(for overlayColor: PieceColor?) -> some View {
    let canShowSlider = vm.moveHistory.count > 0
    return ZStack {
      // Keep constant height (max of slider vs status) to avoid vertical shifts elsewhere.
      Color.clear.frame(height: 54)
      let showForThisBar: Bool = {
        if !showHistorySlider || !canShowSlider { return false }
        if vm.peers.isConnected {
          // Only my overlay bar shows slider in connected mode
          if let my = vm.myColor, overlayColor == my { return true }
          return false
        } else {
          // Single device: show slider only on the owner side
          return overlayColor == historySliderOwner
        }
      }()
      if showForThisBar {
        // History slider replaces status text
        VStack(spacing: 4) {
          HStack {
            Text(vm.historyIndex == nil ? "Live" : "Move \(vm.historyIndex!) / \(vm.moveHistory.count)")
              .font(.caption)
              .padding(.leading, 4)
            Spacer(minLength: 0)
          }
          Slider(value: Binding<Double>(
            get: { Double(vm.historyIndex ?? vm.moveHistory.count) },
            set: { newVal in
              let idx = Int(newVal.rounded())
              let newHistory: Int? = (idx == vm.moveHistory.count ? nil : max(0, min(idx, vm.moveHistory.count)))
              if newHistory == vm.historyIndex { return }
              // Determine if user is scrubbing quickly (dragging) vs discrete taps
              // SwiftUI Slider does not expose drag state directly; assume step-wise if difference is 1
              let current = vm.historyIndex ?? vm.moveHistory.count
              let dist = abs((newHistory ?? vm.moveHistory.count) - current)
              stepHistoryToward(targetIndex: newHistory, animated: dist <= 4)
            }), in: 0...Double(vm.moveHistory.count), step: 1)
            .tint(AppColors.highlight)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      } else if let status = turnStatus(for: overlayColor) {
        Text(status.text)
          .font(.title)
          .foregroundStyle(status.color)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      guard canShowSlider else { return }
      if vm.peers.isConnected {
        // Connected: single bar (mine) controls slider
        if showHistorySlider { hideHistory() } else {
          historySliderOwner = overlayColor
          showHistorySlider = true
        }
      } else {
        // Single device: decide ownership per tap
        if showHistorySlider {
          if historySliderOwner == overlayColor {
            hideHistory()
          } else {
            historySliderOwner = overlayColor
          }
        } else {
            historySliderOwner = overlayColor
            showHistorySlider = true
        }
      }
    }
  }
}


// Local helper (UI-only) mirroring GameViewModel piece values for captured material computation above
private func pieceValue(_ p: Piece) -> Int {
  switch p.type {
  case .queen: return 9
  case .rook: return 5
  case .bishop, .knight: return 3
  case .pawn: return 1
  case .king: return 0
  }
}

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

// Subviews moved to dedicated files: BoardView, SquareView, CapturedRow, PromotionPickerView
