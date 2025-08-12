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
        print("Friendly name:", friendlyName)
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
    // Invitation callback (peer base name, decision closure)
    var onInvitation: ((String, @escaping (Bool)->Void) -> Void)?
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
    // Require confirmation when more than two devices (self + >=2 others) are present.
    if shouldRequireInvitationConfirmation() {
        let base = baseName(from: peerID.displayName)
        onInvitation?(base) { accept in
            invitationHandler(accept, accept ? self.session : nil)
        }
    } else {
        invitationHandler(true, session)
    }
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

    func shouldRequireInvitationConfirmation() -> Bool {
    // If we're already connected to someone, any additional incoming invitation (i.e. a third device) must be confirmed.
    if connectedPeers.count >= 1 { return true }
    // Otherwise (no current connection), allow automatic pairing between first two devices unless we already see 2+ others.
    let discoveredNames = Set(discoveredPeers.map { $0.displayName })
    return discoveredNames.count >= 2
    }

    func baseName(from composite: String) -> String {
        if let idx = composite.firstIndex(of: "#") { return String(composite[..<idx]) }
        return composite
    }
}
