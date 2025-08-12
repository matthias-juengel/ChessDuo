//
//  JoinLobbyView.swift
//  ChessDuo
//
//  View for selecting available hosts to join
//

import SwiftUI

struct JoinLobbyView: View {
    @ObservedObject var peerService: EnhancedPeerService
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Zurück") {
                    peerService.disconnect()
                }
                .foregroundColor(.blue)
                
                Spacer()
                
                Text("Spiel beitreten")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Selbst hosten") {
                    peerService.manualHost()
                }
                .foregroundColor(.blue)
            }
            
            // Hosts list
            if peerService.discoveredHosts.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("Suche nach Spielen...")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text("Stelle sicher, dass das andere Gerät 'Schnellspiel' gedrückt hat")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Verfügbare Spiele:")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ForEach(Array(peerService.discoveredHosts.values.sorted(by: { $0.displayName < $1.displayName })), id: \.deviceId) { host in
                        HostCard(host: host) {
                            peerService.joinHost(host.deviceId)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            // Manual code entry
            VStack(spacing: 12) {
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                Button(action: {
                    // TODO: Implement manual code entry
                }) {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("Mit Code verbinden")
                    }
                    .foregroundColor(.blue)
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            // Keep scanning while in this view
            if !peerService.isConnected {
                peerService.startQuickGame()
            }
        }
    }
}

struct HostCard: View {
    let host: HostCandidate
    let onJoin: () -> Void
    
    var body: some View {
        Button(action: onJoin) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.displayName)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                    
                    HStack {
                        Image(systemName: "wifi")
                            .font(.caption)
                        Text("Bereit zum Spielen")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack {
                    Image(systemName: "gamecontroller.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    Text("Beitreten")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    JoinLobbyView(peerService: EnhancedPeerService())
}