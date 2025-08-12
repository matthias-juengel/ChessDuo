//
//  PeerService.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import Foundation
import MultipeerConnectivity

final class PeerService: NSObject, ObservableObject {
    private let serviceType = "btchess"
    private static let suffixKey = "PeerService.UniqueSuffix"
    private static func uniqueSuffix() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: suffixKey) { return existing }
        let new = String(UUID().uuidString.prefix(8))
        defaults.set(new, forKey: suffixKey)
        return new
    }
    private let friendlyName = UIDevice.current.name
    private lazy var myPeer: MCPeerID = {
        // Composite name ensures uniqueness even if multiple devices share system name.
        let composite = "\(friendlyName)#\(Self.uniqueSuffix())"
        return MCPeerID(displayName: composite)
    }()
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var discoveryTimer: Timer? // legacy (no longer used); kept for safety invalidation only
    private var autoModeActive = false
    private let desiredOpponentCount = 1

    @Published var connectedPeers: [MCPeerID] = []
    // Cache of peerID display names -> friendly names (from hello message)
    @Published var peerFriendlyNames: [String:String] = [:]
    // Discovered (nearby) peers not yet connected
    @Published var discoveredPeers: [MCPeerID] = []

    var localDisplayName: String { myPeer.displayName }
    var localFriendlyName: String { friendlyName }

    override init() {
        super.init()
        session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func startHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func join() {
        browser?.stopBrowsingForPeers()
        browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    /// Symmetric auto mode: advertise and browse simultaneously so that
    /// two devices can discover each other without manual host/join buttons.
    func startAuto() {
    startHosting()
    join()
    autoModeActive = true
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
    session.disconnect()
    discoveryTimer?.invalidate()
    discoveryTimer = nil
    autoModeActive = false
    }

    func send(_ message: NetMessage) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Send error:", error)
        }
    }

    /// Invite a discovered peer (after user confirmation)
    func invite(_ peer: MCPeerID) {
        guard let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 10)
    }

    var isConnected: Bool { !session.connectedPeers.isEmpty }

    // Incoming handler
    var onMessage: ((NetMessage) -> Void)?
    // Notifies when peer list changes
    var onPeerChange: (() -> Void)?
}

extension PeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            // Remove any discovered entries that correspond to now-connected peers (by display name)
            let connectedNames = Set(self.connectedPeers.map { $0.displayName })
            self.discoveredPeers.removeAll { connectedNames.contains($0.displayName) }
            self.onPeerChange?()
            self.adjustDiscoveryTimerForConnectionState()
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let msg = try? JSONDecoder().decode(NetMessage.self, from: data) {
            DispatchQueue.main.async {
                if let name = msg.deviceName { self.peerFriendlyNames[peerID.displayName] = name }
                self.onMessage?(msg)
            }
        }
    }
    // Unused
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
    // Accept all invitations; in our deterministic scheme the larger-name peer
    // should be receiving the invite from the smaller-name peer.
    invitationHandler(true, session)
    }
}

extension PeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Deterministic chooser: only the lexicographically smaller display name
        // will present a prompt to invite the other. The bigger-name peer stays passive
        // and will auto-accept the invitation.
        if myPeer.displayName < peerID.displayName {
            DispatchQueue.main.async {
                // Remove stale entries with same displayName (device restarted -> new peerID)
                self.discoveredPeers.removeAll { $0.displayName == peerID.displayName }
                if !self.connectedPeers.contains(where: { $0.displayName == peerID.displayName }) {
                    self.discoveredPeers.append(peerID)
                }
            }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            // Remove by peer identity or display name (in case restarted peer shows up anew)
            self.discoveredPeers.removeAll { $0 == peerID || $0.displayName == peerID.displayName }
        }
    }
}

// MARK: - Discovery Timer Management
private extension PeerService {
    func adjustDiscoveryTimerForConnectionState() {
        guard autoModeActive else { return }
        let opponentCount = connectedPeers.count
        if opponentCount >= desiredOpponentCount {
            browser?.stopBrowsingForPeers()
        } else {
            if browser == nil {
                browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: serviceType)
                browser?.delegate = self
            }
            browser?.startBrowsingForPeers()
        }
    }
}
