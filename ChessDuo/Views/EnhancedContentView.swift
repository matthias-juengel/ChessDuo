//
//  EnhancedContentView.swift
//  ChessDuo
//
//  Main view with new UX flow orchestration
//

import SwiftUI

struct EnhancedContentView: View {
    @StateObject private var viewModel = EnhancedGameViewModel()
    @State private var selected: Square? = nil
    
    var body: some View {
        ZStack {
            // Background
            backgroundView
            
            // Main content based on connection state
            switch viewModel.peerService.connectionState {
            case .disconnected, .idle:
                HomeView(peerService: viewModel.peerService)
                
            case .proposedHost, .host:
                HostLobbyView(peerService: viewModel.peerService)
                
            case .joiningLobby:
                JoinLobbyView(peerService: viewModel.peerService)
                
            case .pairing:
                PairingView(peerService: viewModel.peerService)
                
            case .gameSetup:
                GameSetupView(peerService: viewModel.peerService)
                
            case .playing:
                GameView(viewModel: viewModel, selected: $selected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
    
    private var backgroundView: some View {
        Group {
            if viewModel.peerService.connectionState == .playing {
                // Game background indicates turn
                let isMyTurn = viewModel.isMyTurn
                Color.black
                if isMyTurn {
                    Color.green.opacity(0.4)
                }
            } else {
                // Default dark background for lobby screens
                Color.black
            }
        }
        .ignoresSafeArea()
    }
}

struct GameView: View {
    @ObservedObject var viewModel: EnhancedGameViewModel
    @Binding var selected: Square?
    
    var body: some View {
        VStack(spacing: 12) {
            // Connection status header
            HStack {
                Text(viewModel.connectionStatus)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Button(action: {
                    // Show connection details/menu
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal)
            
            // Captured pieces (opponent)
            CapturedRow(pieces: viewModel.capturedByOpponent)
            
            // Chess board
            BoardView(
                board: viewModel.engine.board,
                perspective: viewModel.myColor ?? .white,
                myColor: viewModel.myColor ?? .white,
                sideToMove: viewModel.engine.sideToMove,
                selected: $selected
            ) { from, to in
                viewModel.makeMove(from: from, to: to)
            }
            .onChange(of: viewModel.engine.sideToMove) { newValue in
                if let mine = viewModel.myColor, mine != newValue {
                    selected = nil
                }
            }
            
            // Game status
            Text(viewModel.gameStatus)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.vertical, 8)
            
            // Captured pieces (me)
            CapturedRow(pieces: viewModel.capturedByMe)
            
            // Game controls
            HStack(spacing: 16) {
                Button("Aufgeben") {
                    // TODO: Implement resignation
                }
                .foregroundColor(.red)
                .font(.caption)
                
                Spacer()
                
                Button("Rematch") {
                    viewModel.requestRematch()
                }
                .foregroundColor(.blue)
                .font(.caption)
                
                Button("Trennen") {
                    viewModel.peerService.disconnect()
                }
                .foregroundColor(.white.opacity(0.6))
                .font(.caption)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    EnhancedContentView()
}