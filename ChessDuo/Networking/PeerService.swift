//
//  PeerService.swift
//
//  Created by Matthias Jüngel on 10.08.25.
//


import Foundation
import MultipeerConnectivity
import UIKit

final class PeerService: NSObject, ObservableObject {
    private let serviceType = "btchess"
    // When true (set by tests), suppress starting MultipeerConnectivity advertising/browsing
    // to reduce log noise and speed up unit test execution. Connection-dependent logic
    // (session, message routing) remains available for direct injection / simulated messages.
    static var suppressNetworking: Bool = false
    private static let suffixKey = "PeerService.UniqueSuffix"
    private static func uniqueSuffix() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: suffixKey) { return existing }
        let new = String(UUID().uuidString.prefix(8))
        defaults.set(new, forKey: suffixKey)
        return new
    }
    // Immutable base device name (used only for initial peerID construction). User-editable player name is advertised separately.
    private let deviceBaseName = UIDevice.current.name
    @Published private(set) var advertisedName: String
    private lazy var myPeer: MCPeerID = {
        // Composite name ensures uniqueness even if multiple devices share system name or choose identical player names.
        let composite = "\(deviceBaseName)#\(Self.uniqueSuffix())"
        return MCPeerID(displayName: composite)
    }()
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var discoveryTimer: Timer? // legacy (no longer used); kept for safety invalidation only
    private var autoModeActive = false
    private let desiredOpponentCount = 1
    private var browsingActive = false
    private var advertisingActive = false

    @Published var connectedPeers: [MCPeerID] = []
    // Cache of peerID display names -> friendly names (from hello message)
    @Published var peerFriendlyNames: [String:String] = [:]
    // Cache of peerID display names -> advertised names discovered via discoveryInfo BEFORE connection
    @Published var discoveryAdvertisedNames: [String:String] = [:]
    // Persistent cache of last known friendly names (hello messages) keyed by peer displayName
    @Published private(set) var knownPeerFriendlyNames: [String:String] = [:]
    private var advertiseRestartWorkItem: DispatchWorkItem? = nil
    private var advertisingEpoch: Int = 0
    // Discovered (nearby) peers not yet connected
    @Published var discoveredPeers: [MCPeerID] = []
    // Unfiltered list of all browsed peers (including those we intentionally keep passive for auto-handshake logic)
    @Published var allBrowsedPeers: [MCPeerID] = []

    var localDisplayName: String { myPeer.displayName }
    var localFriendlyName: String { advertisedName }

    override init() {
        self.advertisedName = deviceBaseName
        super.init()
        print("Friendly name (base device):", deviceBaseName)
        session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    loadKnownPeerNames()
    }

    /// Update the advertised (player) name. This does NOT change the peerID (cannot for active sessions) but
    /// restarts advertising so new browsers see the updated name via discoveryInfo. Connected peers will learn
    /// the new name when GameViewModel sends a refreshed hello message.
    func updateAdvertisedName(_ name: String) {
        if !Thread.isMainThread { DispatchQueue.main.async { self.updateAdvertisedName(name) }; return }
        guard name != advertisedName else { return }
        advertisedName = name
        print("[ADV] updateAdvertisedName -> \(name)")
        // Debounce restarts slightly so rapid edits don't thrash the radio; also force a lost/found by stopping first.
        advertiseRestartWorkItem?.cancel()
        let epoch = advertisingEpoch + 1; advertisingEpoch = epoch
        // If we're not yet connected to anyone, we pause a little longer to increase the chance the other side's browser
        // emits a lostPeer + foundPeer sequence (MCNearbyServiceBrowser can cache discoveryInfo for a stable peerID otherwise).
        let pause: TimeInterval = isConnected ? 0.4 : 1.0
        let preStopInstant: Bool = !isConnected // if not connected, stop immediately before pause to widen the outage window
        if preStopInstant, advertisingActive {
            advertiser?.stopAdvertisingPeer(); advertisingActive = false
            print("[ADV] Immediate stop to force rediscovery (pre-connection) epoch=\(epoch)")
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.advertisingEpoch == epoch else { return }
            if self.advertisingActive { self.advertiser?.stopAdvertisingPeer(); self.advertisingActive = false; print("[ADV] Stopped advertising for name update epoch=\(epoch) (debounced)") }
            if self.autoModeActive || !self.advertisingActive {
                self.startHosting()
                print("[ADV] Restarted advertising with discoveryInfo pn=\(self.advertisedName) epoch=\(epoch) pause=\(pause)s")
            }
        }
        advertiseRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pause, execute: work)
    }

    func startHosting() {
        if !Thread.isMainThread { DispatchQueue.main.async { self.startHosting() }; return }
        guard !Self.suppressNetworking else { return }
        advertiser?.stopAdvertisingPeer()
        advertisingActive = false
        advertiser?.delegate = nil
        // Provide player name in discoveryInfo so prospective peers can show chosen name prior to connection.
        advertiser = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: ["pn": advertisedName], serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        advertisingActive = true
    }

    func join() {
        if !Thread.isMainThread { DispatchQueue.main.async { self.join() }; return }
        guard !Self.suppressNetworking else { return }
        browser?.stopBrowsingForPeers()
        browsingActive = false
        browser?.delegate = nil
        browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        browsingActive = true
    }

    /// Symmetric auto mode: advertise and browse simultaneously so that
    /// two devices can discover each other without manual host/join buttons.
    func startAuto() {
        if !Thread.isMainThread { DispatchQueue.main.async { self.startAuto() }; return }
        autoModeActive = true
        if !Self.suppressNetworking {
            startHosting()
            join()
        }
    }

    func stop() {
        if !Thread.isMainThread { DispatchQueue.main.async { self.stop() }; return }
        // Prevent auto restarts from delegate callbacks during teardown
        autoModeActive = false

        // Stop advertising
        if advertisingActive { advertiser?.stopAdvertisingPeer(); advertisingActive = false }
        advertiser?.delegate = nil
        advertiser = nil

        // Stop browsing
        if browsingActive { browser?.stopBrowsingForPeers(); browsingActive = false }
        browser?.delegate = nil
        browser = nil

        // Disconnect session last
        session.disconnect()

        discoveryTimer?.invalidate()
        discoveryTimer = nil

        // Clear observable state
        connectedPeers = []
        discoveredPeers = []
        allBrowsedPeers = []
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
                if let name = msg.deviceName, !name.isEmpty {
                    self.peerFriendlyNames[peerID.displayName] = name
                    self.knownPeerFriendlyNames[peerID.displayName] = name
                    self.persistKnownPeerNames()
                    print("[HELLO] Received deviceName for peer composite=\(peerID.displayName) friendly=\(name)")
                }
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
        DispatchQueue.main.async {
            let composite = peerID.displayName
            let advertisedPN = info?["pn"] ?? "<nil>"
            print("[DISCOVERY] Found peer composite=\(composite) advertisedPN=\(advertisedPN)")
            // Maintain unfiltered list (dedupe by display name)
            self.allBrowsedPeers.removeAll { $0.displayName == peerID.displayName }
            self.allBrowsedPeers.append(peerID)
            if let adv = info?["pn"], !adv.isEmpty {
                self.discoveryAdvertisedNames[peerID.displayName] = adv
                // Also cache persistently so future discoveries (before updated advertise) can use it.
                self.knownPeerFriendlyNames[peerID.displayName] = adv
                self.persistKnownPeerNames()
                print("[DISCOVERY] Stored advertised name for \(composite): \(adv)")
            } else if let cached = self.knownPeerFriendlyNames[peerID.displayName] {
                // Use cached friendly name as discovery fallback.
                self.discoveryAdvertisedNames[peerID.displayName] = cached
                print("[DISCOVERY] Using cached friendly name for \(composite): \(cached)")
            }
            if self.myPeer.displayName < peerID.displayName {
                // Filtered prompt list
                self.discoveredPeers.removeAll { $0.displayName == peerID.displayName }
                if !self.connectedPeers.contains(where: { $0.displayName == peerID.displayName }) {
                    self.discoveredPeers.append(peerID)
                    let friendly = self.discoveryAdvertisedNames[peerID.displayName] ?? self.peerFriendlyNames[peerID.displayName] ?? self.baseName(from: peerID.displayName)
                    print("[DISCOVERY] Added to discoveredPeers list: composite=\(composite) shownName=\(friendly)")
                }
            }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            // Remove by peer identity or display name (in case restarted peer shows up anew)
            self.discoveredPeers.removeAll { $0 == peerID || $0.displayName == peerID.displayName }
            self.allBrowsedPeers.removeAll { $0 == peerID || $0.displayName == peerID.displayName }
            self.discoveryAdvertisedNames.removeValue(forKey: peerID.displayName)
            print("[DISCOVERY] Lost peer composite=\(peerID.displayName)")
        }
    }
}

// MARK: - Discovery Timer Management
private extension PeerService {
    // Persistence keys
    private var knownNamesKey: String { "PeerService.KnownFriendlyNames" }

    func loadKnownPeerNames() {
        if let data = UserDefaults.standard.data(forKey: knownNamesKey),
           let dict = try? JSONDecoder().decode([String:String].self, from: data) {
            knownPeerFriendlyNames = dict
        }
    }

    func persistKnownPeerNames() {
        // Bound size to avoid unbounded growth
        if knownPeerFriendlyNames.count > 200 { // arbitrary cap
            // Keep only most recent 150 entries (order not tracked; just drop extras deterministically by key sort)
            let trimmedKeys = Array(knownPeerFriendlyNames.keys.sorted().suffix(150))
            knownPeerFriendlyNames = trimmedKeys.reduce(into: [:]) { acc, k in acc[k] = knownPeerFriendlyNames[k] }
        }
        if let data = try? JSONEncoder().encode(knownPeerFriendlyNames) {
            UserDefaults.standard.set(data, forKey: knownNamesKey)
        }
    }
    func adjustDiscoveryTimerForConnectionState() {
        if !Thread.isMainThread { DispatchQueue.main.async { self.adjustDiscoveryTimerForConnectionState() }; return }
        guard autoModeActive else { return }
        let opponentCount = connectedPeers.count
        if opponentCount >= desiredOpponentCount {
            if browsingActive {
                browser?.stopBrowsingForPeers()
                browsingActive = false
            }
        } else {
            if browser == nil {
                browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: serviceType)
                browser?.delegate = self
            }
            if !browsingActive {
                browser?.startBrowsingForPeers()
                browsingActive = true
            }
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
