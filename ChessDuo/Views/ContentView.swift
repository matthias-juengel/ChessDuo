//
//  ContentView.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import SwiftUI

struct ContentView: View {
  @StateObject private var vm = GameViewModel()
  @State private var selected: Square? = nil
  @State private var showPeerChooser = false
  @State private var selectedPeerToJoin: String? = nil
  @State private var exportFlash: Bool = false

  // Compute status text for a specific overlay perspective (overlayColor).
  private func turnStatus(for overlayColor: PieceColor?) -> (text: String, color: Color)? {
    print("overlayColor", overlayColor)
    switch vm.outcomeForSide(overlayColor ?? vm.engine.sideToMove) {
    case .ongoing:
      let baseColor = vm.engine.sideToMove == .white ? String.loc("turn_white") : String.loc("turn_black")
      let showYou: Bool = {
        if vm.peers.isConnected {
          // Only my own overlay and only if I'm the side to move
          if let mine = vm.myColor, let ov = overlayColor, mine == ov, mine == vm.engine.sideToMove { return true }
          return false
        } else {
          // Single-device: only the overlay whose color is the side to move shows (you)
          if let ov = overlayColor, ov == vm.engine.sideToMove { return true }
          return false
        }
      }()
      let colorText = showYou ? baseColor + " " + String.loc("you_mark") : baseColor
      let fg = vm.engine.sideToMove == .white ? Color.white : Color.black
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
        Button(action: { vm.resetGame() }) {
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
      if vm.outcomeForSide(vm.engine.sideToMove) == .ongoing { // show turn background only while game running
        if vm.peers.isConnected {
          if let my = vm.myColor, vm.engine.sideToMove == my {
            Color.green.opacity(0.4)
          }
        } else {
          // Single-device: highlight only the half belonging to the side to move
          VStack(spacing: 0) {
            if vm.engine.sideToMove == .black {
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

  var boardWithCapturedPieces: some View {
    VStack(spacing: 0) {
      Spacer() // neded to align center with background
      CapturedRow(pieces: vm.capturedByOpponent,
                  rotatePieces: !vm.peers.isConnected,
                  highlightPieceID: vm.lastCaptureByMe == false ? vm.lastCapturedPieceID : nil)
      .padding(.horizontal, 10)
      .padding(.top, 6)
      Color.black.frame(height: 2)
      ZStack {
        Group {
          let inCheck = vm.engine.isInCheck(vm.engine.sideToMove)
          let isMate = inCheck && vm.engine.isCheckmate(for: vm.engine.sideToMove)
          BoardView(board: vm.engine.board,
                    perspective: vm.myColor ?? .white,
                    myColor: vm.myColor ?? .white,
                    sideToMove: vm.engine.sideToMove,
                    inCheckCurrentSide: inCheck,
                    isCheckmatePosition: isMate,
                    singleDevice: !vm.peers.isConnected,
                    lastMove: vm.lastMove,
                    selected: $selected) { from, to, single in
            if single { vm.makeLocalMove(from: from, to: to) } else { vm.makeMove(from: from, to: to) }
          }.onChange(of: vm.engine.sideToMove) { newValue in
            if let mine = vm.myColor, mine != newValue { selected = nil }
          }
        }
      }.aspectRatio(1, contentMode: .fit)
      Color.black.frame(height: 2)
      CapturedRow(pieces: vm.capturedByMe,
                  rotatePieces: false,
                  highlightPieceID: vm.lastCaptureByMe == true ? vm.lastCapturedPieceID : nil)
      .padding(.horizontal, 10)
      .padding(.bottom, 6)
      Spacer() // neded to align center with background
    }
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

      boardWithCapturedPieces.ignoresSafeArea()//.padding([.leading, .trailing], 10)
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
        PromotionPickerView(color: promoColor, rotate180: rotate) { choice in
          vm.promote(to: choice)
        } onCancel: {
          vm.cancelPromotion()
        }
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

// Promotion picker overlay
private struct PromotionPickerView: View {
  let color: PieceColor
  var rotate180: Bool = false
  let onSelect: (PieceType) -> Void
  let onCancel: () -> Void
  private let choices: [PieceType] = [.queen, .rook, .bishop, .knight]
  var body: some View {
    ZStack {
      Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onCancel() }
      VStack(spacing: 16) {
        Text(String.loc("promote_choose"))
          .font(.title2).bold()
          .foregroundColor(.white)
        HStack(spacing: 20) {
          ForEach(choices, id: \.self) { pt in
            Button(action: { onSelect(pt) }) {
              Text(symbol(for: pt, color: color))
                .font(.system(size: 48))
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
          }
        }
        Button(String.loc("cancel")) { onCancel() }
          .font(.title3)
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
          .background(Color.white.opacity(0.85))
          .foregroundColor(.black)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .padding(30)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
      .padding(40)
    }
    .rotationEffect(rotate180 ? .degrees(180) : .degrees(0))
  }
  private func symbol(for t: PieceType, color: PieceColor) -> String {
    switch t {
    case .queen: return color == .white ? "♕" : "♛"
    case .rook: return color == .white ? "♖" : "♜"
    case .bishop: return color == .white ? "♗" : "♝"
    case .knight: return color == .white ? "♘" : "♞"
    case .king: return color == .white ? "♔" : "♚"
    case .pawn: return color == .white ? "♙" : "♟︎"
    }
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
    ZStack {
      Color.clear.frame(height: 30)
      if let status = turnStatus(for: overlayColor) {
        Text(status.text)
          .font(.title)
          .foregroundStyle(status.color)
      }
    }.allowsHitTesting(false)
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

struct CapturedRow: View {
  let pieces: [Piece]
  var rotatePieces: Bool = false
  var highlightPieceID: UUID? = nil
  private let maxBaseSize: CGFloat = 32
  private let minSize: CGFloat = 14
  var body: some View {
    GeometryReader { geo in
      let sorted = sortedPieces()
      // Desired total width with base size & spacing
      let spacing: CGFloat = 4
      let count = CGFloat(sorted.count)
      let available = max(geo.size.width - (count - 1) * spacing, 10)
      let idealSize = min(maxBaseSize, available / max(count, 1))
      let size = max(minSize, idealSize)
      HStack(spacing: spacing) {
        ForEach(sorted.indices, id: \.self) { idx in
          let p = sorted[idx]
          Text(symbol(for: p))
            .font(.system(size: size))
            .foregroundStyle(p.color == .white ? .white : .black)
            .rotationEffect(rotatePieces ? .degrees(180) : .degrees(0))
            .frame(width: size, height: size)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(0.45))
                .opacity(highlightPieceID == p.id ? 1 : 0)
            )
            .animation(.easeInOut(duration: 0.25), value: highlightPieceID)
        }
        Spacer(minLength: 0)
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
    }
    .frame(height: 44)
  }

  private func sortedPieces() -> [Piece] {
    pieces.sorted { pieceValue($0) > pieceValue($1) }
  }

  private func pieceValue(_ p: Piece) -> Int {
    switch p.type {
    case .queen: return 9
    case .rook: return 5
    case .bishop, .knight: return 3
    case .pawn: return 1
    case .king: return 100 // should not normally appear, but ensure it sorts first if present
    }
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

struct BoardView: View {
  let board: Board
  let perspective: PieceColor
  let myColor: PieceColor
  let sideToMove: PieceColor
  let inCheckCurrentSide: Bool
  let isCheckmatePosition: Bool
  let singleDevice: Bool
  let lastMove: Move?
  @Binding var selected: Square?
  let onMove: (Square, Square, Bool) -> Void
  @Namespace private var pieceNamespace
  // Drag state
  @State private var draggingFrom: Square? = nil
  @State private var dragLocation: CGPoint? = nil // local board coords
  @State private var dragTarget: Square? = nil
  @State private var dragOffsetFromCenter: CGSize? = nil
  // Delayed activation state
  @State private var pendingDragFrom: Square? = nil
  @State private var dragStartPoint: CGPoint? = nil
  @State private var dragActivated: Bool = false
  @State private var dragHoldWorkItem: DispatchWorkItem? = nil
  // Track selection state at gesture start to distinguish first tap selection vs. deselect
  @State private var gestureInitialSelected: Square? = nil

  var bodyx: some View {
    VStack {
      Color.red
      Color.blue
    }
  }

  var body: some View {
    GeometryReader { geo in
      let boardSide = min(geo.size.width, geo.size.height)
      let rowArray = rows()
      let colArray = cols()
      let squareSize = boardSide / 8.0
      ZStack(alignment: .topLeading) {
        // Base squares
        ForEach(Array(rowArray.enumerated()), id: \.offset) { rowIdx, rank in
          ForEach(Array(colArray.enumerated()), id: \.offset) { colIdx, file in
            let sq = Square(file: file, rank: rank)
            let piece = board.piece(at: sq)
            let kingInCheckHighlight = inCheckCurrentSide && piece?.type == .king && piece?.color == sideToMove
            let dragHighlight: Bool = {
              // Highlight only when an owned piece is being dragged
              guard let from = draggingFrom else { return false }
              if from == sq { return true }
              if let target = dragTarget, target == sq { return true }
              return false
            }()
            SquareView(square: sq,
                       piece: nil,
                       isSelected: selected == sq,
                       isKingInCheck: kingInCheckHighlight,
                       isKingCheckmated: isCheckmatePosition && kingInCheckHighlight,
                       rotateForOpponent: false,
                       lastMoveHighlight: isLastMoveSquare(sq) || dragHighlight)
            .frame(width: squareSize, height: squareSize)
            .position(x: CGFloat(colIdx) * squareSize + squareSize / 2,
                      y: CGFloat(rowIdx) * squareSize + squareSize / 2)
            .contentShape(Rectangle())
          }
        }
        // Pieces layer (animated)
        ForEach(piecesOnBoard(), id: \.piece.id) { item in
          let rowIdx = rowArray.firstIndex(of: item.square.rank) ?? 0
          let colIdx = colArray.firstIndex(of: item.square.file) ?? 0
          ZStack {
            let showSelectionRing = selected == item.square && !(dragActivated && draggingFrom == item.square)
            if showSelectionRing {
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
                .padding(2)
                .shadow(color: .white.opacity(0.6), radius: 4)
            }
            Text(symbol(for: item.piece))
              .font(.system(size: squareSize * 0.75))
              .foregroundColor(item.piece.color == .white ? .white : .black)
              .rotationEffect(singleDevice && item.piece.color == .black ? .degrees(180) : .degrees(0))
              .scaleEffect(dragActivated && draggingFrom == item.square ? 3.0 : 1.0)
              // Visual lift while dragging: white (or any non-rotated) pieces lift upward, black in single-device mode lifts downward
              // Logical center for targeting remains the unlifted square center (offset applied only visually here)
              .offset(y: {
                guard dragActivated && draggingFrom == item.square else { return 0 }
                let magnitude = 50.0 //squareSize * 0.4 // proportional so it scales with board size / device
                if singleDevice && item.piece.color == .black { return magnitude } // downlift for black side on shared device
                return -magnitude // uplift otherwise
              }())
              .shadow(color: dragActivated && draggingFrom == item.square ? Color.black.opacity(0.4) : Color.clear, radius: 8, x: 0, y: 4)
          }
          .frame(width: squareSize, height: squareSize)
          .position(
            x: positionForPiece(item.square,
                                 defaultPos: CGFloat(colIdx) * squareSize + squareSize / 2,
                                 squareSize: squareSize,
                                 axis: .x),
            y: positionForPiece(item.square,
                                 defaultPos: CGFloat(rowIdx) * squareSize + squareSize / 2,
                                 squareSize: squareSize,
                                 axis: .y)
          )
          .matchedGeometryEffect(id: item.piece.id, in: pieceNamespace)
          .zIndex(zIndexForPiece(item.square))
          .contentShape(Rectangle())
        }

  // Yellow overlay removed; drag highlights handled per-square via lastMoveHighlight flag.
      }
      .frame(width: boardSide, height: boardSide, alignment: .topLeading)
      .contentShape(Rectangle())
      .animation(.easeInOut(duration: 0.35), value: board)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let point = value.location
            if dragStartPoint == nil {
              dragStartPoint = point
              // Capture selection at gesture start
              gestureInitialSelected = selected
            }
            // Establish pending drag square on first touch
            if pendingDragFrom == nil && !dragActivated {
              if let sq = square(at: point, boardSide: boardSide, rowArray: rowArray, colArray: colArray, squareSize: squareSize), canPickUp(square: sq) {
                pendingDragFrom = sq
                selected = sq
                // Schedule hold activation
                let wi = DispatchWorkItem { activateDrag(at: point, boardSide: boardSide, rowArray: rowArray, colArray: colArray, squareSize: squareSize) }
                dragHoldWorkItem?.cancel()
                dragHoldWorkItem = wi
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: wi) // hold delay
              }
            }
            dragLocation = point
            // If not yet activated, check movement threshold
            if !dragActivated, let start = dragStartPoint, let _ = pendingDragFrom {
              let dx = point.x - start.x
              let dy = point.y - start.y
              let dist = sqrt(dx*dx + dy*dy)
              let movementThreshold = max(8, squareSize * 0.08) // device adaptive
              if dist > movementThreshold {
                activateDrag(at: point, boardSide: boardSide, rowArray: rowArray, colArray: colArray, squareSize: squareSize)
              }
            }
            // Update target only when active
            if dragActivated {
              let pieceCenter = adjustedDragCenter(rawPoint: point, squareSize: squareSize)
              dragTarget = square(at: pieceCenter, boardSide: boardSide, rowArray: rowArray, colArray: colArray, squareSize: squareSize)
            } else {
              dragTarget = nil
            }
          }
          .onEnded { value in
            let point = value.location
            let pieceCenter = adjustedDragCenter(rawPoint: point, squareSize: squareSize)
            let releasedSquare = square(at: pieceCenter, boardSide: boardSide, rowArray: rowArray, colArray: colArray, squareSize: squareSize)
            dragHoldWorkItem?.cancel(); dragHoldWorkItem = nil
            // Case 1: Pure tap without initiating drag (drag not activated)
            if !dragActivated {
              if let target = releasedSquare {
                if let sel = selected {
                  if sel == target {
                    // Deselect only if it was already selected before this gesture started
                    if let initial = gestureInitialSelected, initial == sel {
                      withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
                    }
                  } else {
                    // If tapping own piece: change selection, else attempt move
                    let ownershipColor = singleDevice ? sideToMove : myColor
                    if let p = board.piece(at: target), p.color == ownershipColor {
                      withAnimation(.easeInOut(duration: 0.18)) { selected = target }
                    } else {
                      // Attempt move from selected to target
                      onMove(sel, target, singleDevice)
                      withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
                    }
                  }
                } else {
                  // No selection yet: select if own piece
                  let ownershipColor = singleDevice ? sideToMove : myColor
                  if let p = board.piece(at: target), p.color == ownershipColor {
                    withAnimation(.easeInOut(duration: 0.18)) { selected = target }
                  }
                }
              }
              // Cleanup and return
              pendingDragFrom = nil
              draggingFrom = nil
              dragLocation = nil
              dragTarget = nil
              dragOffsetFromCenter = nil
              dragActivated = false
              dragStartPoint = nil
              gestureInitialSelected = nil
              return
            }
            guard let origin = draggingFrom, dragActivated else { return }

            if let release = releasedSquare {
              if origin == release {
                // Tap on same square: if not already selected, select it; else deselect
                if selected != origin {
                  withAnimation(.easeInOut(duration: 0.18)) { selected = origin }
                } else {
                  // Keep selected (classic tap keeps selection) - remove next line to allow deselect
                  // withAnimation { selected = nil }
                }
              } else {
                // Attempt move or selection switch depending on ownership of release square
                let ownershipColor = singleDevice ? sideToMove : myColor
                if let p = board.piece(at: release), p.color == ownershipColor {
                  // Switch selection to another own piece
                  withAnimation(.easeInOut(duration: 0.18)) { selected = release }
                } else if selected == origin {
                  // Perform move
                  onMove(origin, release, singleDevice)
                  withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
                } else {
                  // If origin not currently selected, select origin first (two-step safety)
                  withAnimation(.easeInOut(duration: 0.18)) { selected = origin }
                }
              }
            }
            pendingDragFrom = nil
            draggingFrom = nil
            dragLocation = nil
            dragTarget = nil
            dragOffsetFromCenter = nil
            dragActivated = false
            dragStartPoint = nil
            gestureInitialSelected = nil
          }
      )
    }
  }

  // MARK: - Drag helpers
  private enum Axis { case x, y }
  private func positionForPiece(_ sq: Square, defaultPos: CGFloat, squareSize: CGFloat, axis: Axis) -> CGFloat {
    guard let from = draggingFrom, from == sq, let dragLocation else { return defaultPos }
    var pos: CGFloat = (axis == .x ? dragLocation.x : dragLocation.y)
    if let off = dragOffsetFromCenter {
      pos += (axis == .x ? off.width : off.height)
    }
    // Clamp inside board
    let limit = squareSize * 8
    return min(max(pos, 0), limit)
  }
  // Compute current piece center based on raw finger point + stored offset
  private func adjustedDragCenter(rawPoint: CGPoint, squareSize: CGFloat) -> CGPoint {
    var x = rawPoint.x
    var y = rawPoint.y
    if let off = dragOffsetFromCenter {
      x += off.width
      y += off.height
    }
    let limit = squareSize * 8
    x = min(max(x, 0), limit)
    y = min(max(y, 0), limit)
    return CGPoint(x: x, y: y)
  }
  private func zIndexForPiece(_ sq: Square) -> Double {
    if draggingFrom == sq { return 500 }
    if selected == sq { return 100 }
    return 10
  }
  private func squareFrame(for sq: Square, rowArray: [Int], colArray: [Int], squareSize: CGFloat) -> CGRect? {
    guard let rowIdx = rowArray.firstIndex(of: sq.rank), let colIdx = colArray.firstIndex(of: sq.file) else { return nil }
    let origin = CGPoint(x: CGFloat(colIdx) * squareSize, y: CGFloat(rowIdx) * squareSize)
    return CGRect(origin: origin, size: CGSize(width: squareSize, height: squareSize))
  }
  private func canPickUp(square: Square) -> Bool {
    if singleDevice {
      if let p = board.piece(at: square), p.color == sideToMove { return true }
      return false
    } else {
      if let p = board.piece(at: square), p.color == myColor, myColor == sideToMove { return true }
      return false
    }
  }

  private func rows() -> [Int] {
    perspective == .white ? Array((0..<8).reversed()) : Array(0..<8)
  }
  private func cols() -> [Int] {
    perspective == .white ? Array(0..<8) : Array((0..<8).reversed())
  }

  private func tap(_ sq: Square) {
    // In single-device mode allow either side to move; otherwise restrict to this player's color & turn
    if !singleDevice {
      guard myColor == sideToMove else { return }
    }
    withAnimation(.easeInOut(duration: 0.18)) {
      if let sel = selected {
        if sel == sq {
          // Deselect if tapping the same square
          selected = nil
          return
        }
        // If tapping another own piece, switch selection; otherwise attempt move
        let ownershipColor = singleDevice ? sideToMove : myColor
        if let p = board.piece(at: sq), p.color == ownershipColor {
          selected = sq
        } else {
          onMove(sel, sq, singleDevice)
          selected = nil
        }
      } else {
        // Only allow selecting a square that has a piece of the side to move
        let ownershipColor = singleDevice ? sideToMove : myColor
        if let p = board.piece(at: sq), p.color == ownershipColor {
          selected = sq
        }
      }
    }
  }
  private func piecesOnBoard() -> [(square: Square, piece: Piece)] {
    var list: [(Square, Piece)] = []
    for rank in 0..<8 { for file in 0..<8 { let sq = Square(file: file, rank: rank); if let p = board.piece(at: sq) { list.append((sq,p)) } } }
    return list
  }
  private func symbol(for p: Piece) -> String {
    switch p.type {
    case .king: return "♚"
    case .queen: return "♛"
    case .rook: return "♜"
    case .bishop: return "♝"
    case .knight: return "♞"
    case .pawn: return "♟︎"
    }
  }

  // Rotation logic now handled inline per piece (rotate black pieces only in single-device mode)

  private func square(at point: CGPoint, boardSide: CGFloat, rowArray: [Int], colArray: [Int], squareSize: CGFloat) -> Square? {
    guard point.x >= 0, point.y >= 0, point.x < boardSide, point.y < boardSide else { return nil }
    let colIdx = Int(point.x / squareSize)
    let rowIdx = Int(point.y / squareSize)
    guard rowIdx >= 0 && rowIdx < rowArray.count && colIdx >= 0 && colIdx < colArray.count else { return nil }
    let rank = rowArray[rowIdx]
    let file = colArray[colIdx]
    return Square(file: file, rank: rank)
  }

  // Activate drag: promote pendingDragFrom to draggingFrom, compute initial offset and set dragActivated
  private func activateDrag(at point: CGPoint, boardSide: CGFloat, rowArray: [Int], colArray: [Int], squareSize: CGFloat) {
    guard !dragActivated, let sq = pendingDragFrom else { return }
    draggingFrom = sq
    dragActivated = true
    // Initial offset from touch to piece center
    if let frame = squareFrame(for: sq, rowArray: rowArray, colArray: colArray, squareSize: squareSize) {
      let center = CGPoint(x: frame.midX, y: frame.midY)
      dragOffsetFromCenter = CGSize(width: center.x - point.x, height: center.y - point.y)
    }
  }
}

struct SquareView: View {
  let square: Square
  let piece: Piece?
  let isSelected: Bool
  let isKingInCheck: Bool
  let isKingCheckmated: Bool
  let rotateForOpponent: Bool
  var lastMoveHighlight: Bool = false

  var body: some View {
    ZStack {
      Rectangle()
        .fill(baseColor())
      // if isSelected {
      //   Rectangle().stroke(Color.white, lineWidth: 1).padding(1)
      // }
      if lastMoveHighlight {
        Rectangle()
          .fill(Color.green.opacity(0.45))
      }
      if isKingInCheck {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isKingCheckmated ? Color.red.opacity(0.9) : Color.orange.opacity(0.7))
          .padding(4)
      }
      if let p = piece {
        GeometryReader { geo in
          Text(symbol(for: p))
            .font(.system(size: min(geo.size.width, geo.size.height) * 0.75))
            .foregroundColor(p.color == .white ? .white : .black)
            .opacity(1)
            .rotationEffect(rotateForOpponent ? .degrees(180) : .degrees(0))
            .frame(width: geo.size.width, height: geo.size.height)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func baseColor() -> Color {
    let s = square
    let grayBlack = Color(red: 0.4, green: 0.4, blue: 0.4)
    let grayWhite = Color(red: 0.6, green: 0.6, blue: 0.6)
    return ((s.file + s.rank) % 2 == 0) ? grayBlack : grayWhite

    //    return ((s.file + s.rank) % 2 == 0) ? Color(red: 0.93, green: 0.86, blue: 0.75)
    //    : Color(red: 0.52, green: 0.37, blue: 0.26)
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
}

private extension BoardView {
  func isLastMoveSquare(_ sq: Square) -> Bool {
    guard let mv = lastMove else { return false }
    return mv.from == sq || mv.to == sq
  }
}
