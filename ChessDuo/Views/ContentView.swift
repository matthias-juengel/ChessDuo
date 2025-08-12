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

  var body: some View {
    ZStack {
      //      Full-screen background indicating turn status
      Group {
        let isMyTurn = (vm.myColor != nil) && (vm.engine.sideToMove == (vm.myColor ?? .white))
        Color(red: 0.5, green: 0.5, blue: 0.5)
        if isMyTurn {
          Color.green.opacity(0.4)
        }
      }
      .ignoresSafeArea()

      VStack(spacing: 12) {
        // Reset button area (outside board) with placeholder to keep layout stable
        HStack {
          Spacer()
          Group {
            if vm.movesMade > 0 {
              Button(action: { vm.resetGame() }) {
                Text(vm.awaitingResetConfirmation ? "Neues Spiel?" : "Neues Spiel")
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
              Text("Neues Spiel")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .opacity(0)
            }
          }
        }

        CapturedRow(pieces: vm.capturedByOpponent)

        BoardView(board: vm.engine.board,
                  perspective: vm.myColor ?? .white,
                  myColor: vm.myColor ?? .white,
                  sideToMove: vm.engine.sideToMove,
                  selected: $selected) { from, to in
          vm.makeMove(from: from, to: to)
        }.onChange(of: vm.engine.sideToMove) { newValue in
          if let mine = vm.myColor, mine != newValue {
            selected = nil
          }
        }

        CapturedRow(pieces: vm.capturedByMe)

        ZStack {
          Color.clear.frame(height: 40)
          if vm.peers.isConnected {
            let colorText = vm.engine.sideToMove == .white ? "Weiß" : "Schwarz"
            let turnText = vm.myColor == vm.engine.sideToMove ? "\(colorText) (Du)" : colorText
            Text("Am Zug: \(turnText)")
              .font(.subheadline)
              .foregroundStyle(vm.engine.sideToMove == .white ? .white : .black)
          }
        }

        ZStack {
          Color.clear.frame(height: 40)
          if vm.movesMade == 0, vm.myColor == .some(.white) {
            Button("Schwarz spielen") { vm.swapColorsIfAllowed() }
              .font(.caption2)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(Color.white.opacity(0.9))
              .foregroundColor(.black)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 1))
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
      }
      .padding()
    }
    .onChange(of: vm.discoveredPeerNames) { new in
      // Show chooser when a new peer appears and we're not connected
      if !new.isEmpty && vm.otherDeviceNames.isEmpty {
        showPeerChooser = true
      }
    }
    // Incoming reset request alert
    .alert("Reset annehmen?", isPresented: $vm.incomingResetRequest, actions: {
      Button("Ja") { vm.respondToResetRequest(accept: true) }
      Button("Nein", role: .cancel) { vm.respondToResetRequest(accept: false) }
    }, message: { Text("Der Gegner möchte die Partie zurücksetzen.") })
    // Awaiting confirmation info (outgoing)
    .alert("Warte auf Bestätigung", isPresented: $vm.awaitingResetConfirmation, actions: {
      Button("Abbrechen", role: .destructive) { vm.respondToResetRequest(accept: false) }
    }, message: { Text("Reset-Anfrage gesendet.") })
    .sheet(isPresented: $showPeerChooser) {
      NavigationView {
        List {
          Section("Gefundene Geräte") {
            ForEach(vm.discoveredPeerNames, id: \.self) { name in
              Button(action: { selectedPeerToJoin = name; vm.confirmJoin(peerName: name); showPeerChooser = false }) {
                HStack { Text(name); Spacer(); if selectedPeerToJoin == name { Image(systemName: "checkmark") } }
              }
            }
          }
          if vm.discoveredPeerNames.isEmpty {
            Text("Keine Geräte gefunden")
          }
        }
        .navigationTitle("Beitreten?")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showPeerChooser = false } } }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
  }
}

struct CapturedRow: View {
  let pieces: [Piece]
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
          Text(symbol(for: p))
            .font(.system(size: 30))
            .foregroundStyle(p.color == .white ? .white : .black)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 2)
    }
    .frame(maxHeight: 28)
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
  @Binding var selected: Square?
  let onMove: (Square, Square) -> Void

  var body: some View {
    let files = 0..<8
    let ranks = 0..<8
    VStack(spacing: 0) {
      ForEach(rows(), id: \.self) { rank in
        HStack(spacing: 0) {
          ForEach(cols(), id: \.self) { file in
            let sq = Square(file: file, rank: rank)
            SquareView(square: sq,
                       piece: board.piece(at: sq),
                       isSelected: selected == sq).zIndex(selected == sq ? 100 : 1)
            .onTapGesture { tap(sq) }
          }
        }.zIndex(selected?.rank == rank ? 100 : 1)
      }
    }
    .aspectRatio(1, contentMode: .fit)
//    .clipShape(RoundedRectangle(cornerRadius: 8))
//    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 1))
    .overlay(Rectangle().stroke(.black, lineWidth: 1))
  }

  private func rows() -> [Int] {
    perspective == .white ? Array((0..<8).reversed()) : Array(0..<8)
  }
  private func cols() -> [Int] {
    perspective == .white ? Array(0..<8) : Array((0..<8).reversed())
  }

  private func tap(_ sq: Square) {
    // Only interact when it's this player's turn
    guard myColor == sideToMove else { return }
    if let sel = selected {
      if sel == sq {
        // Deselect if tapping the same square
        selected = nil
        return
      }
      // If tapping another own piece, switch selection; otherwise attempt move
      if let p = board.piece(at: sq), p.color == myColor {
        selected = sq
      } else {
        onMove(sel, sq)
        selected = nil
      }
    } else {
      // Only allow selecting a square that has a piece of the side to move
      if let p = board.piece(at: sq), p.color == myColor {
        selected = sq
      }
    }
  }
}

struct SquareView: View {
  let square: Square
  let piece: Piece?
  let isSelected: Bool

  var body: some View {
    ZStack {
      Rectangle()
        .fill(colorForSquare(square))
      if isSelected {
        Rectangle().stroke(Color.white, lineWidth: 1).padding(1)
      }
      if let p = piece {
        Text(symbol(for: p))
          .font(.system(size: 35))
          .foregroundColor(p.color == .white ? .white : .black)
          .opacity(1)
        //                    .bold()
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
