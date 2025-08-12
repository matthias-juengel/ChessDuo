//
//  HomeView.swift
//  ChessDuo
//
//  Home screen with new UX flow
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var peerService: EnhancedPeerService
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App title
            Text("ChessDuo")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Chess board preview (small)
            BoardPreviewView()
                .frame(width: 120, height: 120)
            
            Spacer()
            
            // Main action button
            Button(action: {
                peerService.startQuickGame()
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Schnellspiel")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Nearby games section
            if !peerService.discoveredHosts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("In der Nähe")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ForEach(Array(peerService.discoveredHosts.values), id: \.deviceId) { host in
                        NearbyGameCard(host: host) {
                            peerService.joinHost(host.deviceId)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Manual options
            HStack {
                Button("Selbst hosten") {
                    peerService.manualHost()
                }
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Code eingeben") {
                    // TODO: Implement manual code entry
                }
                .foregroundColor(.blue)
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct NearbyGameCard: View {
    let host: HostCandidate
    let onJoin: () -> Void
    
    var body: some View {
        Button(action: onJoin) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spiel von \(host.displayName) gefunden")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                    
                    Text("Tippen zum Beitreten")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct BoardPreviewView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        Rectangle()
                            .fill((row + col) % 2 == 0 ? Color.gray.opacity(0.3) : Color.gray.opacity(0.6))
                            .frame(width: 30, height: 30)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.3), lineWidth: 1))
    }
}