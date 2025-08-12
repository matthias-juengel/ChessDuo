//
//  GameSetupView.swift
//  ChessDuo
//
//  Game configuration screen with auto-countdown
//

import SwiftUI

struct GameSetupView: View {
    @ObservedObject var peerService: EnhancedPeerService
    @State private var countdown: Int = 3
    @State private var countdownTimer: Timer?
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Header
            VStack(spacing: 16) {
                Text("Spiel-Einstellungen")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Verbunden mit \(peerService.connectedPeer?.displayName ?? "Unbekannt")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Settings
            VStack(spacing: 24) {
                // Color selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Wer spielt Weiß?")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ForEach(GameSetup.ColorChoice.allCases, id: \.self) { choice in
                        ColorChoiceButton(
                            choice: choice,
                            isSelected: peerService.gameSetup.colorChoice == choice
                        ) {
                            peerService.gameSetup.colorChoice = choice
                            restartCountdown()
                        }
                    }
                }
                
                // Time control
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bedenkzeit")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(GameSetup.TimeControl.allCases, id: \.self) { timeControl in
                                TimeControlButton(
                                    timeControl: timeControl,
                                    isSelected: peerService.gameSetup.timeControl == timeControl
                                ) {
                                    peerService.gameSetup.timeControl = timeControl
                                    restartCountdown()
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            Spacer()
            
            // Countdown and start button
            VStack(spacing: 16) {
                if countdown > 0 {
                    VStack(spacing: 8) {
                        Text("Spiel startet in")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("\(countdown)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                
                Button(action: {
                    startGame()
                }) {
                    Text("Jetzt starten")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            stopCountdown()
        }
    }
    
    private func startCountdown() {
        countdown = 3
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                startGame()
            }
        }
    }
    
    private func restartCountdown() {
        stopCountdown()
        startCountdown()
    }
    
    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    private func startGame() {
        stopCountdown()
        peerService.finalizeGameStart()
    }
}

struct ColorChoiceButton: View {
    let choice: GameSetup.ColorChoice
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                
                Text(choice.rawValue)
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding()
            .background(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct TimeControlButton: View {
    let timeControl: GameSetup.TimeControl
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(timeControl.rawValue)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(isSelected ? Color.white : Color.gray.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

#Preview {
    GameSetupView(peerService: EnhancedPeerService())
}