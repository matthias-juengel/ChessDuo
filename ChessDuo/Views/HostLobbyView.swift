//
//  HostLobbyView.swift
//  ChessDuo
//
//  Host waiting screen with pairing code
//

import SwiftUI

struct HostLobbyView: View {
    @ObservedObject var peerService: EnhancedPeerService
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Status
            VStack(spacing: 16) {
                Image(systemName: "wifi.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Bereit als Host")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Andere Geräte sehen dich jetzt")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Pairing code (if available)
            if let code = peerService.currentPairingCode {
                VStack(spacing: 12) {
                    Text("Verbindungs-Code")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text(code)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // Also show emoji version
                        Text(PairingCode.generateEmoji())
                            .font(.title)
                            .padding()
                            .background(Color.blue.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Text("Teile diesen Code mit deinem Mitspieler")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Waiting for connection
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    
                    Text("Warte auf Mitspieler...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            
            Spacer()
            
            // Help text
            Text("Tipp: Sag deinem Gegenüber, nach 'ChessDuo' zu suchen oder gib den Code weiter.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Cancel button
            Button("Abbrechen") {
                peerService.disconnect()
            }
            .foregroundColor(.red)
            .padding()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    HostLobbyView(peerService: EnhancedPeerService())
}