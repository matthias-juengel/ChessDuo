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
    switch vm.outcome {
    case .ongoing:
//      guard !vm.peers.isConnected else { return nil }
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
    Group {
      if vm.movesMade > 0 {
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
      Spacer() // neded to align center with background
      CapturedRow(pieces: vm.capturedByOpponent,
                  rotatePieces: !vm.peers.isConnected,
                  highlightPieceID: vm.lastCaptureByMe == false ? vm.lastCapturedPieceID : nil)
      .padding(10)
      .frame(height: 50)
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
        .padding(10)
        .frame(height: 50)
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
      viewBackground.ignoresSafeArea()
      boardWithCapturedPieces.ignoresSafeArea()//.padding([.leading, .trailing], 10)
      overlayControls
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

private extension ContentView {
  var overlayControls: some View {
    VStack {
      Spacer().allowsHitTesting(false)
      statusBar
      controlBar
    }
  }

  var statusBar: some View {
    ZStack {
      Color.clear.frame(height: 30)
      if let status = turnStatus {
        Text(status.text)
          .font(.title)
          .foregroundStyle(status.color)
      }
    }.allowsHitTesting(false)
  }

  var controlBar: some View {
    ZStack {
      Color.clear.frame(height: 30)
      if vm.movesMade == 0, vm.myColor == .some(.white) {
        swapColorButton
      }
      resetButtonArea
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
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(sortedPieces().indices, id: \.self) { idx in
          let p = sortedPieces()[idx]
          ZStack {
            Text(symbol(for: p))
              .font(.system(size: 32))
              .foregroundStyle(p.color == .white ? .white : .black)
              .rotationEffect(rotatePieces ? .degrees(180) : .degrees(0))
              .padding(2)
            if highlightPieceID == p.id {
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(0.45))
                .blendMode(.plusLighter)
            }
          }
          .animation(.easeInOut(duration: 0.3), value: highlightPieceID)
        }
      }
      .padding(.vertical, 2)
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
            SquareView(square: sq,
                       piece: nil,
                       isSelected: selected == sq,
                       isKingInCheck: kingInCheckHighlight,
                       isKingCheckmated: isCheckmatePosition && kingInCheckHighlight,
                       rotateForOpponent: false,
                       lastMoveHighlight: isLastMoveSquare(sq))
              .frame(width: squareSize, height: squareSize)
              .position(x: CGFloat(colIdx) * squareSize + squareSize / 2,
                        y: CGFloat(rowIdx) * squareSize + squareSize / 2)
              .contentShape(Rectangle())
              .onTapGesture { tap(sq) }
          }
        }
        // Pieces layer (animated)
        ForEach(piecesOnBoard(), id: \.piece.id) { item in
          let rowIdx = rowArray.firstIndex(of: item.square.rank) ?? 0
          let colIdx = colArray.firstIndex(of: item.square.file) ?? 0
          ZStack {
            if selected == item.square {
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
                .padding(2)
                .shadow(color: .white.opacity(0.6), radius: 4)
            }
            Text(symbol(for: item.piece))
              .font(.system(size: squareSize * 0.75))
              .foregroundColor(item.piece.color == .white ? .white : .black)
              .rotationEffect(singleDevice && item.piece.color == .black ? .degrees(180) : .degrees(0))
          }
          .frame(width: squareSize, height: squareSize)
          .position(x: CGFloat(colIdx) * squareSize + squareSize / 2,
                    y: CGFloat(rowIdx) * squareSize + squareSize / 2)
          .matchedGeometryEffect(id: item.piece.id, in: pieceNamespace)
          .zIndex(selected == item.square ? 100 : 10)
          .contentShape(Rectangle())
          // .onTapGesture { tap(item.square) }
        }
        // // Border overlay
        // Rectangle()
        //   .stroke(Color.black, lineWidth: 2)
        //   .frame(width: boardSide, height: boardSide)
      }
      .frame(width: boardSide, height: boardSide, alignment: .topLeading)
      .contentShape(Rectangle())
      .animation(.easeInOut(duration: 0.35), value: board)
      .gesture(
        DragGesture(minimumDistance: 0)
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
          .fill(isKingCheckmated ? Color.red.opacity(0.9) : Color.red.opacity(0.7))
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
