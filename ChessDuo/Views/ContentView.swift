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

  private var turnStatus: (text: String, color: Color)? {
    guard vm.peers.isConnected else { return nil }
    switch vm.outcome {
    case .ongoing:
      let baseColor = vm.engine.sideToMove == .white ? String.loc("turn_white") : String.loc("turn_black")
      let colorText: String = {
        if vm.myColor == vm.engine.sideToMove { return baseColor + " " + String.loc("you_mark") }
        return baseColor
      }()
      let fg = vm.engine.sideToMove == .white ? Color.white : Color.black
      return (String.loc("turn_prefix", colorText), fg)
    case .win: return (String.loc("win_text"), .green)
    case .loss: return (String.loc("loss_text"), .red)
    case .draw: return (String.loc("draw_text"), .yellow)
    }
  }

  private var resetButtonArea: some View {
    HStack {
      Spacer()
      Group {
        if vm.movesMade > 0 {
          Button(action: { vm.resetGame() }) {
            Text(vm.awaitingResetConfirmation ? String.loc("new_game_confirm") : String.loc("new_game"))
              .font(.caption2)
              .fontWeight(.semibold)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(Color.white.opacity(vm.awaitingResetConfirmation ? 0.7 : 0.9))
              .foregroundColor(.black)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 1))
          }
          .disabled(!vm.peers.isConnected)
          .transition(.opacity)
        } else {
          Text(String.loc("new_game"))
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .opacity(0)
        }
      }
    }
  }

  var viewBackground: some View {
    // Full-screen background indicating turn status
    ZStack {
      Color(red: 0.5, green: 0.5, blue: 0.5)
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

  var boardWithCapturedPieces: some View {
    VStack(spacing: 0) {
      CapturedRow(pieces: vm.capturedByOpponent, rotatePieces: !vm.peers.isConnected)
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
                  selected: $selected) { from, to, single in
          if single { vm.makeLocalMove(from: from, to: to) } else { vm.makeMove(from: from, to: to) }
        }.onChange(of: vm.engine.sideToMove) { newValue in
          if let mine = vm.myColor, mine != newValue { selected = nil }
        }
      }

      CapturedRow(pieces: vm.capturedByMe, rotatePieces: false)
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
      viewBackground.ignoresSafeArea()
      boardWithCapturedPieces.ignoresSafeArea()//.padding([.leading, .trailing], 5)

      VStack {
        Spacer().allowsHitTesting(false)
        ZStack {
          Color.clear.frame(height: 30)
          if let status = turnStatus {
            Text(status.text)
              .font(.headline)
              .foregroundStyle(status.color)
          }
        }.allowsHitTesting(false)
        ZStack {
          Color.clear.frame(height: 30)
          if vm.movesMade == 0, vm.myColor == .some(.white) {
            Button(String.loc("play_black")) { vm.swapColorsIfAllowed() }
              .font(.caption2)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(Color.white.opacity(0.9))
              .foregroundColor(.black)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 1))
          }
          resetButtonArea
        }
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

struct CapturedRow: View {
  let pieces: [Piece]
  var rotatePieces: Bool = false
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(sortedPieces().indices, id: \.self) { idx in
          let p = sortedPieces()[idx]
          Text(symbol(for: p))
            .font(.system(size: 30))
            .foregroundStyle(p.color == .white ? .white : .black)
            .rotationEffect(rotatePieces ? .degrees(180) : .degrees(0))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 2)
    }
    .frame(maxHeight: 28)
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
  @Binding var selected: Square?
  let onMove: (Square, Square, Bool) -> Void

  var body: some View {
    GeometryReader { geo in
      let boardSide = min(geo.size.width, geo.size.height)
      let rowArray = rows()
      let colArray = cols()
      let squareSize = boardSide / 8.0
      ZStack(alignment: .topLeading) {
        // Squares + pieces
        ForEach(Array(rowArray.enumerated()), id: \.offset) { rowIdx, rank in
          ForEach(Array(colArray.enumerated()), id: \.offset) { colIdx, file in
            let sq = Square(file: file, rank: rank)
            let piece = board.piece(at: sq)
            let kingInCheckHighlight = inCheckCurrentSide && piece?.type == .king && piece?.color == sideToMove
            SquareView(square: sq,
                       piece: piece,
                       isSelected: selected == sq,
                       isKingInCheck: kingInCheckHighlight,
                       isKingCheckmated: isCheckmatePosition && kingInCheckHighlight,
                       rotateForOpponent: singleDevice && (piece?.color == .black))
              .frame(width: squareSize, height: squareSize)
              .position(x: CGFloat(colIdx) * squareSize + squareSize / 2,
                        y: CGFloat(rowIdx) * squareSize + squareSize / 2)
              .contentShape(Rectangle())
              .zIndex(selected == sq ? 100 : 1)
          }
        }
        // Border overlay
//        Rectangle()
//          .stroke(Color.black, lineWidth: 1)
//          .frame(width: boardSide, height: boardSide)
      }
      .frame(width: boardSide, height: boardSide, alignment: .topLeading)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            // Live feedback: show selection of origin square if none selected yet
            if selected == nil,
               let origin = square(
                 at: value.startLocation,
                 boardSide: boardSide,
                 rowArray: rowArray,
                 colArray: colArray,
                 squareSize: squareSize
               ) {
              selected = origin
            }
          }
          .onEnded { value in
            let start = value.startLocation
            let end = value.location
            guard let startSq = square(
              at: start,
              boardSide: boardSide,
              rowArray: rowArray,
              colArray: colArray,
              squareSize: squareSize
            ) else { return }
            let endSq = square(
              at: end,
              boardSide: boardSide,
              rowArray: rowArray,
              colArray: colArray,
              squareSize: squareSize
            ) ?? startSq
            if startSq == endSq {
              tap(startSq)
            } else {
              if selected != startSq { selected = startSq }
              if selected == startSq { tap(endSq) }
            }
          }
      )
      .clipped()
      .aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

struct SquareView: View {
  let square: Square
  let piece: Piece?
  let isSelected: Bool
  let isKingInCheck: Bool
  let isKingCheckmated: Bool
  let rotateForOpponent: Bool

  var body: some View {
    ZStack {
      Rectangle()
        .fill(colorForSquare(square))
      if isSelected {
        Rectangle().stroke(Color.white, lineWidth: 1).padding(1)
      }
      if isKingInCheck {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isKingCheckmated ? Color.red.opacity(0.9) : Color.red.opacity(0.7))
          .padding(4)
      }
      if let p = piece {
        Text(symbol(for: p))
          .font(.system(size: 35))
          .foregroundColor(p.color == .white ? .white : .black)
          .opacity(1)
          .rotationEffect(rotateForOpponent ? .degrees(180) : .degrees(0))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func colorForSquare(_ s: Square) -> Color {
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
