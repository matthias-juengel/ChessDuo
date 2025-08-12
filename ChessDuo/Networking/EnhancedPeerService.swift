//
//  EnhancedPeerService.swift
//  ChessDuo
//
//  Enhanced networking service for new UX implementation
//

import Foundation
import MultipeerConnectivity
import Combine
import UIKit

final class EnhancedPeerService: NSObject, ObservableObject {
    private let serviceType = "btchess"
    private let deviceId = UUID().uuidString
    private let myPeer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    // Published state
    @Published var connectionState: ConnectionState = .idle
    @Published var peerStatus: PeerStatus = .available
    @Published var discoveredHosts: [String: HostCandidate] = [:]
    @Published var connectedPeer: MCPeerID?
    @Published var currentPairingCode: String?
    @Published var gameSetup: GameSetup = GameSetup()
    
    // Timers for state transitions
    private var proposedHostTimer: Timer?
    private var pairingTimer: Timer?
    private var gameSetupTimer: Timer?
    
    // Callbacks
    var onMessage: ((NetMessage) -> Void)?
    var onConnectionEstablished: (() -> Void)?
    var onConnectionLost: (() -> Void)?
    
    var localDisplayName: String { myPeer.displayName }
    var isConnected: Bool { session.connectedPeers.count > 0 }
    
    override init() {
        myPeer = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }
    
    // MARK: - Public Interface
    
    func startQuickGame() {
        connectionState = .idle
        startScanning()
        startAdvertising()
        
        // Start timer for proposed host transition
        proposedHostTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.becomeProposedHost()
        }
    }
    
    func manualHost() {
        stopAllTimers()
        peerStatus = .host
        connectionState = .host
        updateAdvertising()
        print("Manual host mode")
    }
    
    func joinHost(_ hostId: String) {
        guard let candidate = discoveredHosts[hostId] else { return }
        connectionState = .joiningLobby
        
        // Send join request to specific host
        let msg = NetMessage(kind: .joinRequest, deviceName: localDisplayName)
        msg.deviceId = deviceId
        
        // Find the peer by display name and send join request
        if let peer = session.connectedPeers.first(where: { $0.displayName.contains(candidate.displayName) }) {
            sendMessage(msg, to: [peer])
        }
    }
    
    func sendPairingCode(_ code: String) {
        let msg = NetMessage(kind: .pairingCode)
        msg.pairingCode = code
        sendMessage(msg)
    }
    
    func startGameSetup() {
        connectionState = .gameSetup
        
        // Auto-start timer (3 seconds)
        gameSetupTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.finalizeGameStart()
        }
    }
    
    func finalizeGameStart() {
        stopAllTimers()
        connectionState = .playing
        
        let msg = NetMessage(kind: .gameStart)
        msg.gameSetup = gameSetup
        sendMessage(msg)
        
        onConnectionEstablished?()
    }
    
    func disconnect() {
        stopAllTimers()
        stopScanning()
        stopAdvertising()
        session.disconnect()
        connectionState = .disconnected
        connectedPeer = nil
        discoveredHosts.removeAll()
        currentPairingCode = nil
    }
    
    func sendMessage(_ message: NetMessage, to peers: [MCPeerID]? = nil) {
        let targetPeers = peers ?? session.connectedPeers
        guard !targetPeers.isEmpty else { return }
        
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: targetPeers, with: .reliable)
        } catch {
            print("Send error:", error)
        }
    }
    
    // MARK: - Private Implementation
    
    private func startScanning() {
        browser?.stopBrowsingForPeers()
        browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }
    
    private func startAdvertising() {
        stopAdvertising()
        let discoveryInfo = [
            "status": peerStatus.rawValue,
            "deviceId": deviceId
        ]
        advertiser = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: discoveryInfo, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }
    
    private func updateAdvertising() {
        if advertiser != nil {
            startAdvertising() // Restart with new info
        }
    }
    
    private func stopScanning() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }
    
    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }
    
    private func stopAllTimers() {
        proposedHostTimer?.invalidate()
        pairingTimer?.invalidate()
        gameSetupTimer?.invalidate()
        proposedHostTimer = nil
        pairingTimer = nil
        gameSetupTimer = nil
    }
    
    private func becomeProposedHost() {
        guard connectionState == .idle else { return }
        
        // Check if we found any active hosts
        if discoveredHosts.values.contains(where: { candidate in
            candidate.deviceId != deviceId // Don't count ourselves
        }) {
            // Found other hosts, stay in lobby mode
            connectionState = .joiningLobby
            return
        }
        
        // No hosts found, become proposed host
        peerStatus = .proposedHost
        connectionState = .proposedHost
        updateAdvertising()
        
        // Check for host election conflicts
        performHostElection()
    }
    
    private func performHostElection() {
        let proposedHosts = discoveredHosts.values.filter { candidate in
            // This would need to be determined from peer status, simplified for now
            candidate.deviceId != deviceId
        }
        
        let myCandidate = HostCandidate(
            deviceId: deviceId,
            displayName: localDisplayName,
            rssi: nil,
            timestamp: Date()
        )
        
        var allCandidates = Array(proposedHosts)
        allCandidates.append(myCandidate)
        
        let winner = allCandidates.min()
        
        if winner?.deviceId == deviceId {
            // We won the election
            peerStatus = .host
            connectionState = .host
            updateAdvertising()
            print("Won host election")
        } else {
            // Someone else won, become available for joining
            peerStatus = .available
            connectionState = .joiningLobby
            updateAdvertising()
            print("Lost host election to \(winner?.displayName ?? "unknown")")
        }
    }
    
    private func handleJoinRequest(_ message: NetMessage, from peer: MCPeerID) {
        guard peerStatus == .host || peerStatus == .proposedHost else { return }
        
        // Generate pairing code
        currentPairingCode = PairingCode.generate()
        connectionState = .pairing
        connectedPeer = peer
        
        // Send response with pairing code
        let response = NetMessage(kind: .joinResponse)
        response.pairingCode = currentPairingCode
        response.deviceName = localDisplayName
        sendMessage(response, to: [peer])
        
        // Start pairing timeout
        pairingTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] _ in
            self?.handlePairingTimeout()
        }
        
        print("Join request from \(peer.displayName), code: \(currentPairingCode ?? "none")")
    }
    
    private func handleJoinResponse(_ message: NetMessage, from peer: MCPeerID) {
        guard connectionState == .joiningLobby else { return }
        
        currentPairingCode = message.pairingCode
        connectionState = .pairing
        connectedPeer = peer
        
        print("Received pairing code: \(currentPairingCode ?? "none")")
    }
    
    private func handlePairingCode(_ message: NetMessage, from peer: MCPeerID) {
        guard let receivedCode = message.pairingCode,
              let expectedCode = currentPairingCode,
              connectionState == .pairing else { return }
        
        if receivedCode == expectedCode {
            // Pairing successful
            stopAllTimers()
            startGameSetup()
            print("Pairing successful")
        } else {
            // Pairing failed
            handlePairingTimeout()
            print("Pairing failed: wrong code")
        }
    }
    
    private func handlePairingTimeout() {
        stopAllTimers()
        currentPairingCode = nil
        connectedPeer = nil
        
        // Return to appropriate state
        if peerStatus == .host {
            connectionState = .host
        } else {
            connectionState = .joiningLobby
        }
        
        print("Pairing timed out")
    }
}

// MARK: - MCSessionDelegate

extension EnhancedPeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("Connected to \(peerID.displayName)")
            case .connecting:
                print("Connecting to \(peerID.displayName)")
            case .notConnected:
                print("Disconnected from \(peerID.displayName)")
                if self.connectedPeer == peerID {
                    self.onConnectionLost?()
                    self.connectedPeer = nil
                    if self.connectionState == .playing {
                        self.connectionState = .disconnected
                    }
                }
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        
        DispatchQueue.main.async {
            self.handleMessage(message, from: peerID)
            self.onMessage?(message)
        }
    }
    
    private func handleMessage(_ message: NetMessage, from peer: MCPeerID) {
        switch message.kind {
        case .statusUpdate:
            // Update discovered hosts based on status
            if let deviceId = message.deviceId,
               let status = message.peerStatus {
                let candidate = HostCandidate(
                    deviceId: deviceId,
                    displayName: message.deviceName ?? peer.displayName,
                    rssi: nil,
                    timestamp: Date()
                )
                
                if status == .host || status == .proposedHost {
                    discoveredHosts[deviceId] = candidate
                } else {
                    discoveredHosts.removeValue(forKey: deviceId)
                }
            }
            
        case .joinRequest:
            handleJoinRequest(message, from: peer)
            
        case .joinResponse:
            handleJoinResponse(message, from: peer)
            
        case .pairingCode:
            handlePairingCode(message, from: peer)
            
        case .gameStart:
            if let setup = message.gameSetup {
                gameSetup = setup
            }
            connectionState = .playing
            onConnectionEstablished?()
            
        default:
            break // Let GameViewModel handle game-specific messages
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension EnhancedPeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept all invitations in the new flow
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension EnhancedPeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Auto-invite to establish connection for messaging
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        
        // Parse discovery info to update host list
        if let deviceId = info?["deviceId"],
           let statusString = info?["status"],
           let status = PeerStatus(rawValue: statusString) {
            
            let candidate = HostCandidate(
                deviceId: deviceId,
                displayName: peerID.displayName,
                rssi: nil,
                timestamp: Date()
            )
            
            DispatchQueue.main.async {
                if status == .host || status == .proposedHost {
                    self.discoveredHosts[deviceId] = candidate
                } else {
                    self.discoveredHosts.removeValue(forKey: deviceId)
                }
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Remove from discovered hosts if we lose the peer
        DispatchQueue.main.async {
            self.discoveredHosts = self.discoveredHosts.filter { $0.value.displayName != peerID.displayName }
        }
    }
}