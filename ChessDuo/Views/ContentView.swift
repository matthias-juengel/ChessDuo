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
    case .win: return (String.loc("win_text"), .green)
    case .loss: return (String.loc("loss_text"), .red)
    case .draw: return (String.loc("draw_text"), .yellow)
    }
  }

  private func resetButtonArea(for overlayColor: PieceColor?) -> some View {
    Group {
      let canShow: Bool = {
        if vm.movesMade == 0 { return false }
        if vm.peers.isConnected {
          guard let my = vm.myColor, let oc = overlayColor else { return false }
          return oc == my && my == vm.engine.sideToMove
        } else {
          guard let oc = overlayColor else { return false }
          return oc == vm.engine.sideToMove
        }
      }()
      if canShow {
        Button(action: {
          // Exit history/slider to avoid interaction lock after reset
          hideHistory()
          vm.resetGame()
        }) {
          Text(vm.peers.isConnected && vm.awaitingResetConfirmation ? String.loc("new_game_confirm") : String.loc("new_game"))
            .font(.title3)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(vm.peers.isConnected && vm.awaitingResetConfirmation ? 0.7 : 0.9))
            .foregroundColor(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 1))
        }
        .transition(.opacity)
      } else {
        Text(String.loc("new_game"))
          .font(.title3)
          .fontWeight(.semibold)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .opacity(0)
      }
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
            Color.green.opacity(0.4)
          }
        } else {
          // Single-device: highlight only the half belonging to the side to move
          VStack(spacing: 0) {
            if currentSideToMove == .black {
              Color.green.opacity(0.38)
              Color.clear
            } else {
              Color.clear
              Color.green.opacity(0.38)
            }
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
    let topSide: PieceColor = vm.peers.isConnected ? ((vm.myColor == .white) ? .black : .white) : .black
    let bottomSide: PieceColor = vm.peers.isConnected ? (vm.myColor ?? .white) : .white
    let whiteCaps = ctx.whiteCaptures
    let blackCaps = ctx.blackCaptures
    let topPieces = topSide == .black ? blackCaps : whiteCaps
    let bottomPieces = bottomSide == .white ? whiteCaps : blackCaps
    return VStack(spacing: 0) {
      Spacer(minLength: 0)
      capturedRow(for: topSide, pieces: topPieces, ctx: ctx, whiteLead: whiteLead, blackLead: blackLead, rotate: !vm.peers.isConnected)
        .padding(.horizontal, 10).padding(.top, 6)
      Color.black.frame(height: 2)
      chessBoard
      Color.black.frame(height: 2)
      capturedRow(for: bottomSide, pieces: bottomPieces, ctx: ctx, whiteLead: whiteLead, blackLead: blackLead, rotate: false)
        .padding(.horizontal, 10).padding(.bottom, 6)
      Spacer(minLength: 0)
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
      perspective: vm.myColor ?? .white,
      myColor: vm.myColor ?? .white,
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
        // Removed board tap gesture; handled inside BoardView gesture
      if vm.peers.isConnected {
        overlayControls(for: vm.myColor) // show only my side
      } else {
        // Single-device: show both sides explicitly with fixed colors
        overlayControls(for: .white)
        overlayControls(for: .black)
          .rotationEffect(.degrees(180))
          .zIndex(400)
      }
      if vm.showingPromotionPicker, let pending = vm.pendingPromotionMove {
        let promoColor = vm.engine.board.piece(at: pending.from)?.color ?? vm.engine.sideToMove.opposite
        let rotate = !vm.peers.isConnected && promoColor == .black
        PromotionPickerView(color: promoColor, rotate180: rotate, onSelect: { vm.promote(to: $0) }, onCancel: { vm.cancelPromotion() })
          .transition(.scale.combined(with: .opacity))
          .zIndex(500)
          .ignoresSafeArea()
      }
  if exportFlash { Text("Copied state")
          .padding(8)
          .background(Color.black.opacity(0.7))
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .transition(.opacity)
          .zIndex(900)
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
    }
    // Incoming reset request alert
    .alert(String.loc("reset_accept_title"), isPresented: $vm.incomingResetRequest, actions: {
      Button(String.loc("reset_accept_yes")) { vm.respondToResetRequest(accept: true) }
      Button(String.loc("reset_accept_no"), role: .cancel) { vm.respondToResetRequest(accept: false) }
    }, message: { Text(String.loc("opponent_requests_reset")) })
    // Awaiting confirmation info (outgoing) - single neutral button to cancel request
    .alert(isPresented: $vm.awaitingResetConfirmation) {
      Alert(title: Text(String.loc("awaiting_confirmation_title")),
            message: Text(String.loc("reset_request_sent")),
            dismissButton: .cancel(Text(String.loc("reset_cancel_request"))) {
        vm.respondToResetRequest(accept: false)
      })
    }
    // Offline new game confirmation
    .alert(String.loc("offline_new_game_title"), isPresented: $vm.offlineResetPrompt, actions: {
      Button(String.loc("offline_new_game_keep"), role: .cancel) { vm.offlineResetPrompt = false }
      Button(String.loc("offline_new_game_confirm"), role: .destructive) { vm.performLocalReset(send: false) }
    }, message: { Text(String.loc("offline_new_game_message")) })
    .sheet(isPresented: $showPeerChooser) {
      NavigationView {
        List {
          Section(String.loc("found_devices_section")) {
            ForEach(vm.discoveredPeerNames, id: \.self) { name in
              Button(action: { selectedPeerToJoin = name; vm.confirmJoin(peerName: name); showPeerChooser = false }) {
                HStack { Text(name); Spacer(); if selectedPeerToJoin == name { Image(systemName: "checkmark") } }
              }
            }
          }
          if vm.discoveredPeerNames.isEmpty {
            Text(String.loc("no_devices_found"))
          }
        }
        .navigationTitle(String.loc("join_title"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String.loc("cancel")) { showPeerChooser = false } } }
      }
    }
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
  func overlayControls(for color: PieceColor?) -> some View {
    VStack {
      Spacer().allowsHitTesting(false)
      statusBar(for: color)
      controlBar(for: color)
    }
  }

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
            .tint(.green)
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

  func controlBar(for overlayColor: PieceColor?) -> some View {
    ZStack {
      Color.clear.frame(height: 30)
      if vm.movesMade == 0, vm.myColor == .some(.white), vm.peers.isConnected { // swap only relevant connected pre-game
        swapColorButton
      }
      resetButtonArea(for: overlayColor)
    }
  }

  var swapColorButton: some View {
    Button(String.loc("play_black")) { vm.swapColorsIfAllowed() }
      .font(.title)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(Color.white.opacity(0.9))
      .foregroundColor(.black)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 1))
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
