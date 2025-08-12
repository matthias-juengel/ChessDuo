//
//  ChessComponents.swift
//  ChessDuo
//
//  Shared UI components for chess game
//

import SwiftUI

// MARK: - Chess Board Components

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colorForSquare(_ s: Square) -> Color {
        let grayBlack = Color(red: 0.4, green: 0.4, blue: 0.4)
        let grayWhite = Color(red: 0.6, green: 0.6, blue: 0.6)
        return ((s.file + s.rank) % 2 == 0) ? grayBlack : grayWhite
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

// MARK: - Captured Pieces Display

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