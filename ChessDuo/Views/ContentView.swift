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

    var body: some View {
        VStack(spacing: 12) {
            Text("Bluetooth Chess")
                .font(.title.bold())

            HStack {
                Button("Host (Weiß)") { vm.host() }
                Button("Join (Schwarz)") { vm.join() }
                Button("Reset") { vm.resetGame() }.disabled(!vm.peers.isConnected)
                Button("Trennen") { vm.disconnect() }
            }
            .buttonStyle(.bordered)

            Text(vm.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            BoardView(board: vm.engine.board,
                      perspective: vm.myColor ?? .white,
                      selected: $selected) { from, to in
                vm.makeMove(from: from, to: to)
            }

            Text("Du spielst: \(vm.myColor?.rawValue.capitalized ?? "—") • Am Zug: \(vm.engine.sideToMove == .white ? "Weiß" : "Schwarz")")
                .font(.footnote)
        }
        .padding()
    }
}

struct BoardView: View {
    let board: Board
    let perspective: PieceColor
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
                                   isSelected: selected == sq)
                        .onTapGesture { tap(sq) }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary, lineWidth: 1))
    }

    private func rows() -> [Int] {
        perspective == .white ? Array((0..<8).reversed()) : Array(0..<8)
    }
    private func cols() -> [Int] {
        perspective == .white ? Array(0..<8) : Array((0..<8).reversed())
    }

    private func tap(_ sq: Square) {
        if let sel = selected {
            if sel == sq {
                selected = nil
            } else {
                onMove(sel, sq)
                selected = nil
            }
        } else {
            // Nur eigene Figuren auswählen (optional – wenn Farbe bekannt)
            selected = sq
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
                Rectangle().stroke(Color.yellow, lineWidth: 3)
            }
            if let p = piece {
                Text(symbol(for: p))
                    .font(.system(size: 30))
                    .foregroundColor(p.color == .white ? .white : .black)
                    .opacity(1)
                    .bold()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colorForSquare(_ s: Square) -> Color {
        ((s.file + s.rank) % 2 == 0) ? Color(red: 0.93, green: 0.86, blue: 0.75)
                                     : Color(red: 0.52, green: 0.37, blue: 0.26)
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
