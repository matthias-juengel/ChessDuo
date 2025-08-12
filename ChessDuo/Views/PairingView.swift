//
//  PairingView.swift
//  ChessDuo
//
//  Code verification screen
//

import SwiftUI

struct PairingView: View {
    @ObservedObject var peerService: EnhancedPeerService
    @State private var enteredCode: String = ""
    @State private var showError: Bool = false
    
    var isHost: Bool {
        peerService.peerStatus == .host
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Header
            VStack(spacing: 16) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                if isHost {
                    Text("Verbindet mit \(peerService.connectedPeer?.displayName ?? "Unbekannt")")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Bestätige Code")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
            
            // Code display/input
            if isHost {
                // Host shows the code
                if let code = peerService.currentPairingCode {
                    VStack(spacing: 16) {
                        Text("Zeige diesen Code:")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 16) {
                            Text(code)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            Text(PairingCode.emojiForCode(code))
                                .font(.largeTitle)
                                .padding()
                                .background(Color.blue.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Text("Der andere Spieler muss diesen Code eingeben")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                // Joiner enters the code
                VStack(spacing: 16) {
                    Text("Gib den Code ein, der auf \(peerService.connectedPeer?.displayName ?? "dem anderen Gerät") angezeigt wird:")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    // Code input field
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            DigitInputField(
                                digit: enteredCode.count > index ? String(enteredCode[enteredCode.index(enteredCode.startIndex, offsetBy: index)]) : "",
                                isActive: enteredCode.count == index
                            )
                        }
                    }
                    
                    // Number pad
                    NumberPadView { digit in
                        if enteredCode.count < 4 {
                            enteredCode += digit
                            if enteredCode.count == 4 {
                                verifyCode()
                            }
                        }
                    } onDelete: {
                        if !enteredCode.isEmpty {
                            enteredCode.removeLast()
                        }
                    }
                    
                    if showError {
                        Text("Falscher Code. Versuche es erneut.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            Spacer()
            
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
    
    private func verifyCode() {
        peerService.sendPairingCode(enteredCode)
        
        // Reset after a brief delay if wrong
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if peerService.connectionState == .pairing {
                showError = true
                enteredCode = ""
                
                // Hide error after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showError = false
                }
            }
        }
    }
}

struct DigitInputField: View {
    let digit: String
    let isActive: Bool
    
    var body: some View {
        Text(digit)
            .font(.title)
            .fontWeight(.bold)
            .foregroundColor(digit.isEmpty ? .clear : .white)
            .frame(width: 50, height: 60)
            .background(isActive ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? .blue : .clear, lineWidth: 2)
            )
    }
}

struct NumberPadView: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    
    private let digits = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(digits, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { digit in
                        Button(action: {
                            if digit == "⌫" {
                                onDelete()
                            } else if !digit.isEmpty {
                                onDigit(digit)
                            }
                        }) {
                            Text(digit)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 50)
                                .background(digit.isEmpty ? Color.clear : Color.gray.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(digit.isEmpty)
                    }
                }
            }
        }
    }
}

#Preview {
    PairingView(peerService: EnhancedPeerService())
}