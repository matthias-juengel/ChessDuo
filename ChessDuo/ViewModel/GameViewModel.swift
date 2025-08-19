//
//  GameViewModel.swift
//
//  Created by Matthias Jüngel on 10.08.25.
//

import Foundation
import Combine
import SwiftUI

final class GameViewModel: ObservableObject {
  // Was @Published private(set); relaxed to allow extension-based persistence & loaders to assign.
  @Published var engine = ChessEngine()
  // New: Player name persistence and publication
  @AppStorage("playerName") private var storedPlayerName: String = ""
  @Published var playerName: String = UIDevice.current.name // default device name
  @Published var showInitialNamePrompt: Bool = false
  // New onboarding sequencing: show an in-app explanation before triggering iOS local network permission prompt.
  @AppStorage("hasSeenNetworkPermissionIntro") var hasSeenNetworkPermissionIntro: Bool = false
  @Published var showNetworkPermissionIntro: Bool = false
  // Opponent name convenience (first connected friendly name if any)
  var opponentName: String? { otherDeviceNames.first }
  /// Assigned multiplayer color (nil in single-device mode). Persisted across reconnects
  /// when a game is in progress so that killing one app does not flip sides.
  @Published var myColor: PieceColor? = nil {
    didSet {
      guard !suppressPersistMyColor else { return }
      if let c = myColor {
        persistedMyColorRaw = c.rawValue
        // Sync preferred perspective with multiplayer color when connected so single-device fallback matches.
        if peers.isConnected { preferredPerspective = c }
      } else {
        if movesMade == 0 { persistedMyColorRaw = "" } // only clear if no game in progress
      }
    }
  }
  // User preference for bottom perspective in single-device mode (persisted). When connected,
  // this is automatically synced to myColor so if the peer disconnects mid-game, orientation stays.
  @AppStorage("preferredPerspective") private var preferredPerspectiveRaw: String = PieceColor.white.rawValue
  var preferredPerspective: PieceColor {
    get { PieceColor(rawValue: preferredPerspectiveRaw) ?? .white }
    set { preferredPerspectiveRaw = newValue.rawValue }
  }
  // Persist last assigned multiplayer color so reconnect keeps roles mid-game.
  @AppStorage("persistedMyColor") private var persistedMyColorRaw: String = ""
  private var suppressPersistMyColor = false
  @Published var otherDeviceNames: [String] = []
  @Published var discoveredPeerNames: [String] = [] // for UI prompt (friendly names without unique suffix)
  @Published var allBrowsedPeerNames: [String] = [] // complete unfiltered list for menu display
  // Friendly names for all browsed peers (uses advertised/hello names if available) for menu & join UI
  @Published var allBrowsedPeerFriendlyNames: [String] = []
  @Published var capturedByMe: [Piece] = []
  @Published var capturedByOpponent: [Piece] = []
  // Stable archives of actual captured piece objects, order of capture.
  // whiteCapturedPieces = pieces originally belonging to White that have been captured.
  // blackCapturedPieces = pieces originally belonging to Black that have been captured.
  var whiteCapturedPieces: [Piece] = []
  var blackCapturedPieces: [Piece] = []
  @Published var movesMade: Int = 0
  @Published var awaitingResetConfirmation: Bool = false
  @Published var incomingResetRequest: Bool = false
  // History revert negotiation (multiplayer)
  @Published var awaitingHistoryRevertConfirmation: Bool = false // I requested revert and wait
  @Published var incomingHistoryRevertRequest: Int? = nil // opponent requested revert to this move count
  @Published var requestedHistoryRevertTarget: Int? = nil // outgoing revert target while awaiting
  @Published var lastAppliedHistoryRevertTarget: Int? = nil // set when revert applied for UI
  // Famous game load negotiation
  @Published var awaitingLoadGameConfirmation: Bool = false // I requested to load a famous game
  @Published var incomingLoadGameRequestTitle: String? = nil // opponent wants to load a game with this title
  var pendingGameToLoad: FamousGame? = nil // (internal) locally selected game awaiting acceptance shared with FamousGame extension
//  @Published var outcome: GameOutcome = .ongoing
  @Published var incomingJoinRequestPeer: String? = nil
  @Published var offlineResetPrompt: Bool = false
  @Published var lastMove: Move? = nil
  @Published var lastCapturedPieceID: UUID? = nil
  @Published var lastCaptureByMe: Bool? = nil
  // Promotion handling
  @Published var pendingPromotionMove: Move? = nil // move without promotion yet
  @Published var showingPromotionPicker: Bool = false
  // Move history & time-travel
  @Published var moveHistory: [Move] = [] // sequence of all executed moves (local or remote)
  // When not nil represents index into moveHistory (number of moves applied) for historical view.
  // Nil means live current engine state.
  @Published var historyIndex: Int? = nil
  // Board snapshots after each applied move (index 0 = initial position, i = board after i moves).
  // Provides stable Piece.id continuity across adjacent history states for matchedGeometryEffect animations.
  @Published var boardSnapshots: [Board] = []
  // Remote history view sync
  @Published var remoteIsDrivingHistoryView: Bool = false // true while we reflect a peer's slider movement
  var suppressHistoryViewBroadcast = false // internal for history/broadcast logic in extensions
  // Tracks whether any live moves have been made since last reset or famous game load
  // Was private; split extensions need to update it (persistence load)
  var sessionProgressed: Bool = false

  // Cache for legal destination queries: key = (boardSignature, originSquare)
  // Was private; widened to fileprivate for extension access after file split.
  var legalDestCache: [String: Set<Square>] = [:]
  var lastCacheBoardSignature: String? = nil

  // Baseline (initial) board & side for current session (handles FEN starts for famous games)
  // Widened to fileprivate for history / capture / persistence extensions.
  var baselineBoard: Board = Board.initial()
  // Baseline piece counts per color/type (used to compute captures for history & FEN starts)
  var baselineCounts: [PieceColor: [PieceType:Int]] = [.white: [:], .black: [:]]
  var baselineSideToMove: PieceColor = .white
  // Whether the baseline is trusted as the true starting state for moveHistory (v3 persistence or fresh session)
  var baselineTrusted: Bool = true

  // Export current game state as a textual snapshot (for debugging / tests)
  func exportText() -> String {
    // Ensure status is up to date before exporting (fallback safety)
//    recomputeOutcomeIfNeeded()
    var lines: [String] = []
    lines.append("MyChessboardExport v1")
    // Board in FEN-style ranks 8..1
    lines.append("Board:")
    for rank in (0..<8).reversed() { // 7 down to 0
      var fenRank = ""
      var emptyCount = 0
      for file in 0..<8 {
        let sq = Square(file: file, rank: rank)
        if let p = engine.board.piece(at: sq) {
          if emptyCount > 0 { fenRank.append(String(emptyCount)); emptyCount = 0 }
          fenRank.append(pieceChar(p))
        } else {
          emptyCount += 1
        }
      }
      if emptyCount > 0 { fenRank.append(String(emptyCount)) }
      lines.append(fenRank)
    }
    lines.append("SideToMove: \(engine.sideToMove == .white ? "w" : "b")")
    lines.append("MovesMade: \(movesMade)")
    if let lm = lastMove { lines.append("LastMove: \(algebraic(lm.from))->\(algebraic(lm.to))") }
//    lines.append("Outcome: \(outcomeString(outcome))")
    // Captured pieces (approximate perspective neutral): compute missing from initial for each color
    lines.append("CapturedWhite: \(capturedPiecesDescription(color: .white))")
    lines.append("CapturedBlack: \(capturedPiecesDescription(color: .black))")
    let legal = engine.generateLegalMoves(for: engine.sideToMove)
      .map { "\(algebraic($0.from))->\(algebraic($0.to))" }
      .sorted()
    lines.append("LegalMoves: \(legal.joined(separator: ","))")
    let side = engine.sideToMove
    lines.append("InCheck: \(engine.isInCheck(side) ? "1" : "0")")
    lines.append("Checkmate: \(engine.isCheckmate(for: side) ? "1" : "0")")
    lines.append("Stalemate: \(engine.isStalemate(for: side) ? "1" : "0")")
    return lines.joined(separator: "\n")
  }

  // Static helper needed by multiple extensions / observers after file split.
  static func baseName(from composite: String) -> String {
    if let idx = composite.firstIndex(of: "#") { return String(composite[..<idx]) }
    return composite
  }

  // Centralized piece material valuation (king = 0 for advantage math)
  static func materialValue(_ piece: Piece) -> Int {
    switch piece.type {
    case .queen: return 9
    case .rook: return 5
    case .bishop, .knight: return 3
    case .pawn: return 1
    case .king: return 0
    }
  }

  // Lightweight internal board equality used during initialization to detect persistence load differences
  private func boardsEqualInternal(_ a: Board, _ b: Board) -> Bool {
    for rank in 0..<8 { for file in 0..<8 {
      let sq = Square(file: file, rank: rank)
      let pa = a.piece(at: sq)
      let pb = b.piece(at: sq)
      if pa?.type != pb?.type || pa?.color != pb?.color { return false }
    }}
    return true
  }

  private func pieceChar(_ p: Piece) -> String {
    let map: [PieceType:String] = [.king:"k", .queen:"q", .rook:"r", .bishop:"b", .knight:"n", .pawn:"p"]
    let base = map[p.type] ?? "?"
    return p.color == .white ? base.uppercased() : base
  }
  private func algebraic(_ sq: Square) -> String {
    let files = "abcdefgh"
    let fileChar = files[files.index(files.startIndex, offsetBy: sq.file)]
    return "\(fileChar)\(sq.rank + 1)"
  }
  // MARK: - Baseline-aware capture reconstruction (for history & FEN starts)
  // Widened to fileprivate so persistence & capture reconstruction can reuse.
  func pieceCounts(on board: Board) -> [PieceColor: [PieceType:Int]] {
    var counts: [PieceColor: [PieceType:Int]] = [.white: [:], .black: [:]]
    for rank in 0..<8 {
      for file in 0..<8 {
        let sq = Square(file: file, rank: rank)
        if let p = board.piece(at: sq) {
          counts[p.color]![p.type, default: 0] += 1
        }
      }
    }
    return counts
  }

  /// Missing piece counts vs. baseline for each color
  func missingComparedToBaseline(current: Board) -> (whiteMissing: [PieceType:Int], blackMissing: [PieceType:Int]) {
    let curr = pieceCounts(on: current)
    var whiteMiss: [PieceType:Int] = [:], blackMiss: [PieceType:Int] = [:]
    for t in [PieceType.king, .queen, .rook, .bishop, .knight, .pawn] {
      let bW = baselineCounts[.white]?[t] ?? 0, cW = curr[.white]?[t] ?? 0
      let bB = baselineCounts[.black]?[t] ?? 0, cB = curr[.black]?[t] ?? 0
      if bW > cW { whiteMiss[t] = bW - cW }
      if bB > cB { blackMiss[t] = bB - cB }
    }
    return (whiteMiss, blackMiss)
  }

  /// Rebuild published capture lists for a given board according to current perspective
  func rebuildCapturedLists(for board: Board) {
    let (whiteMissing, blackMissing) = missingComparedToBaseline(current: board)
    // Ensure archives contain at least the number of missing pieces per color (if we started mid-game via FEN we may fabricate placeholders once).
    func ensureArchive(color: PieceColor, missing: [PieceType:Int]) {
      for t in [PieceType.queen, .rook, .bishop, .knight, .pawn] {
        let needed = missing[t] ?? 0
        var archive = (color == .white) ? whiteCapturedPieces : blackCapturedPieces
        let existingOfType = archive.filter { $0.type == t }.count
        if existingOfType < needed {
          // Fabricate placeholders only for deficit (no original IDs available). These won't highlight as current capture.
          for _ in existingOfType..<needed { archive.append(Piece(type: t, color: color)) }
          if color == .white { whiteCapturedPieces = archive } else { blackCapturedPieces = archive }
        }
      }
    }
    ensureArchive(color: .white, missing: whiteMissing)
    ensureArchive(color: .black, missing: blackMissing)

    let perspective: PieceColor = myColor ?? preferredPerspective
    let opponentColor: PieceColor = perspective.opposite

    // Build perspective-relative lists from archives, trimming to the missing counts per type (ordered by capture chronology)
    func listFor(color: PieceColor, missing: [PieceType:Int]) -> [Piece] {
      let archive = (color == .white) ? whiteCapturedPieces : blackCapturedPieces
      var result: [Piece] = []
      // Keep chronological order but limit per type counts so stale fabricated overflow after piece returns (shouldn't happen) is ignored.
      var remainingPerType: [PieceType:Int] = missing
      for piece in archive {
        let left = remainingPerType[piece.type] ?? 0
        if left > 0 {
          result.append(piece)
          remainingPerType[piece.type] = left - 1
        }
      }
      return result
    }

    let whiteList = listFor(color: .white, missing: whiteMissing)
    let blackList = listFor(color: .black, missing: blackMissing)

    // Map to perspective-specific published arrays
    capturedByMe = (perspective == .white) ? blackList : whiteList
    capturedByOpponent = (perspective == .white) ? whiteList : blackList
  }
  private func outcomeString(_ o: GameOutcome) -> String {
    switch o { case .ongoing: return "ongoing"; case .win: return "win"; case .loss: return "loss"; case .draw: return "draw" }
  }
  private func capturedPiecesDescription(color: PieceColor) -> String {
    // Count initial pieces per color
    var initial: [PieceType:Int] = [.king:1, .queen:1, .rook:2, .bishop:2, .knight:2, .pawn:8]
    // Subtract those still on board
    for rank in 0..<8 { for file in 0..<8 { let sq = Square(file: file, rank: rank); if let p = engine.board.piece(at: sq), p.color == color { initial[p.type, default:0] -= 1 } } }
    // Build string
    return initial.compactMap { (type, missing) in missing > 0 ? "\(missing)x\(pieceChar(Piece(type: type, color: color)))" : nil }.sorted().joined(separator: ",")
  }
  // (Outcome & game completion helpers moved to GameViewModel+MoveExecution.swift)

  let peers = PeerService()
  private var cancellables: Set<AnyCancellable> = []
  private var hasSentHello = false
  var pendingInvitationDecision: ((Bool)->Void)? = nil // internal so networking extension can respond
  enum GameOutcome: Equatable { case ongoing, win, loss, draw }
  // Internal gate so we don't start Multipeer advertising/browsing (which triggers the iOS Local Network prompt)
  // until the user has explicitly continued past the network permission intro.
  private var networkingApproved: Bool = false
  // Expose read-only flag for UI (e.g. menu) to conditionally show an "Enable Nearby Play" action.
  var needsNetworkingApproval: Bool { !networkingApproved }
  // Allow UI to re-present the intro if user postponed earlier (only when not yet approved).
  func requestNetworkingApproval() {
    guard !networkingApproved else { return }
    if !showNetworkPermissionIntro { showNetworkPermissionIntro = true }
  }
  // Heuristic: after starting networking, if no peers discovered/connected after a grace period, assume permission denied.
  @Published var localNetworkPermissionLikelyDenied: Bool = false
  @Published var showLocalNetworkPermissionHelp: Bool = false
  private var permissionCheckWorkItem: DispatchWorkItem? = nil
  /// Schedule a one-off heuristic check a few seconds after networking starts.
  private func scheduleLocalNetworkPermissionHeuristic() {
    permissionCheckWorkItem?.cancel()
    guard networkingApproved else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      // If still no activity (no connected peers, no discovered, no browsed) flag probable denial.
      if self.peers.connectedPeers.isEmpty && self.otherDeviceNames.isEmpty && self.discoveredPeerNames.isEmpty && self.allBrowsedPeerNames.isEmpty {
        // Avoid false positives for brand new sessions by requiring at least some time since approval.
        self.localNetworkPermissionLikelyDenied = true
      }
    }
    permissionCheckWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
  }
  /// Open the app's Settings page so user can enable Local Network permission.
  @MainActor func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }

  init() {
  // 1. Determine initial player name & whether we must show the name chooser.
    if storedPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      playerName = UIDevice.current.name
      showInitialNamePrompt = true // cold start without stored name -> show name chooser first
      print("[VM] First launch: presenting name chooser before anything else")
    } else {
      playerName = storedPlayerName
    }
    // 2. If name already known AND user has NOT yet seen the network intro -> present intro next.
    if !showInitialNamePrompt && !hasSeenNetworkPermissionIntro {
      showNetworkPermissionIntro = true
      print("[VM] Showing network permission intro (name already set)")
    }
  // Networking approval mirrors whether intro already seen (previous sessions). Only auto-start when approved.
  networkingApproved = hasSeenNetworkPermissionIntro
    // 3. Only start networking automatically if BOTH name is set AND intro already seen.
    if !showInitialNamePrompt && networkingApproved {
      peers.updateAdvertisedName(playerName)
      peers.startAuto()
      print("[VM] Auto-started networking (prerequisites satisfied)")
      scheduleLocalNetworkPermissionHeuristic()
    } else {
      print("[VM] Networking start deferred (namePrompt=\(showInitialNamePrompt) introSeen=\(hasSeenNetworkPermissionIntro))")
    }
  // Attempt to load persisted game before starting networking so board state is restored.
  // NOTE: We must not overwrite the restored baseline (baselineBoard, baselineSideToMove, baselineCounts, baselineTrusted)
  // after this call. We'll capture whether load succeeded via a local flag.
  let preLoadEngine = engine
  loadGameIfAvailable()
  let loadedFromPersistence = (movesMade > 0 || baselineTrusted == true) && !boardsEqualInternal(preLoadEngine.board, engine.board)
  // Restore myColor from persistent storage if moves have been made and value exists
  if movesMade > 0, let stored = PieceColor(rawValue: persistedMyColorRaw), myColor == nil {
    myColor = stored
  }
  // Falls beim Laden (z.B. V1/V2 ohne History snapshots) keine Snapshots erzeugt wurden, initialisieren wir minimal.
  if boardSnapshots.isEmpty { boardSnapshots = [engine.board] }
  // Only set baseline for a brand-new session (no persistence load or famous game applied yet).
  if !loadedFromPersistence {
    baselineBoard = engine.board
    baselineSideToMove = engine.sideToMove
    baselineCounts = pieceCounts(on: baselineBoard)
    baselineTrusted = true
  }
  rebuildCapturedLists(for: engine.board)
    peers.onMessage = { [weak self] msg in
      self?.handle(msg)
    }
    peers.onPeerChange = { [weak self] in
      DispatchQueue.main.async { self?.attemptRoleProposalIfNeeded() }
    }
    peers.onInvitation = { [weak self] peerName, decision in
      guard let self = self else { return }
      DispatchQueue.main.async {
        self.incomingJoinRequestPeer = peerName
        self.pendingInvitationDecision = decision
      }
    }

    // Mirror connected peer names into a published property for the UI (strip suffix unless friendly map has real name)
    peers.$connectedPeers
      .combineLatest(peers.$peerFriendlyNames, peers.$discoveryAdvertisedNames)
      .map { peerIDs, friendlyMap, discoveryMap in
        peerIDs.map { peer in
          if let friendly = friendlyMap[peer.displayName] { return friendly }
          if let adv = discoveryMap[peer.displayName] { return adv }
          return Self.baseName(from: peer.displayName)
        }.sorted()
      }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] names in
        self?.otherDeviceNames = names
      }
      .store(in: &cancellables)

    // Observe connection changes to trigger automatic negotiation.
    peers.$connectedPeers
      .receive(on: DispatchQueue.main)
      .sink { [weak self] peers in
        guard let self = self else { return }
        if !peers.isEmpty {
          // If we had already been playing locally (single-device) and moves exist, preserve that this device is White.
          if self.myColor == nil, self.movesMade > 0 {
            self.myColor = .white
            // (Optional) Align perspective with newly fixed color to avoid sudden flip.
            self.preferredPerspective = .white
            // Proactively announce role so the peer adopts black.
            self.peers.send(.init(kind: .proposeRole))
          }
          if !self.hasSentHello { self.sendHello(); self.hasSentHello = true }
          self.attemptRoleProposalIfNeeded()
          // Initiate state sync (both sides may request; reconciliation chooses higher move count)
          self.requestSync()
        } else {
          // Do NOT clear myColor if a game is in progress; keep color stable for potential reconnect.
          if self.movesMade == 0 {
            self.myColor = nil
            self.persistedMyColorRaw = ""
          }
          self.hasSentHello = false
        }
      }
      .store(in: &cancellables)


    // Mirror discovered peers to names for confirmation UI (strip suffix)
    peers.$discoveredPeers
      .combineLatest(peers.$peerFriendlyNames, peers.$discoveryAdvertisedNames)
      .map { peerIDs, friendlyMap, discoveryMap in
        peerIDs.map { peer in
          if let f = friendlyMap[peer.displayName] { return f }
          if let adv = discoveryMap[peer.displayName] { return adv }
          return Self.baseName(from: peer.displayName)
        }.sorted()
      }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] names in
        print("[VM] discoveredPeerNames updated -> \(names)")
        self?.discoveredPeerNames = names
      }
      .store(in: &cancellables)

    // Mirror ALL browsed peers to names (unfiltered) for menu listing
    peers.$allBrowsedPeers
      .map { $0.map { Self.baseName(from: $0.displayName) }.sorted() }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] names in self?.allBrowsedPeerNames = names }
      .store(in: &cancellables)

    // Mirror ALL browsed peers to friendly names (prefer hello/discovery advertised mapping where possible)
    peers.$allBrowsedPeers
      .combineLatest(peers.$peerFriendlyNames, peers.$discoveryAdvertisedNames)
      .map { peerIDs, friendlyMap, discoveryMap in
        peerIDs.map { peer in
          if let f = friendlyMap[peer.displayName] { return f }
          if let adv = discoveryMap[peer.displayName] { return adv }
          return Self.baseName(from: peer.displayName)
        }.sorted()
      }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] names in
        print("[VM] allBrowsedPeerFriendlyNames updated -> \(names)")
        self?.allBrowsedPeerFriendlyNames = names
      }
      .store(in: &cancellables)

  // (Removed previous unconditional auto-start block; networking now only starts when both
  // name chooser finished and intro acknowledged.)

    // Observe historyIndex changes to broadcast history view state (only when we initiate changes locally)
    $historyIndex
      .removeDuplicates { $0 == $1 }
      .sink { [weak self] idx in
        guard let self = self else { return }
        if self.suppressHistoryViewBroadcast { return }
        // Only send if connected and change represents entering an older state or exiting.
        guard self.peers.isConnected else { return }
        // Send message: if idx is nil -> live view, else index value.
        self.peers.send(.init(kind: .historyView, historyViewIndex: idx))
      }
      .store(in: &cancellables)

    // Recompute capture lists whenever history index changes (baseline diff)
    $historyIndex
      .removeDuplicates { $0 == $1 }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] idx in
        guard let self = self else { return }
        let board = idx.map { self.boardAfterMoves($0) } ?? self.engine.board
        self.rebuildCapturedLists(for: board)
      }
      .store(in: &cancellables)
  }

  // User accepted to connect with a given peer name
  func confirmJoin(peerName: String) {
    // UI now may show one of: friendly hello name, advertised discovery name, or stripped base name.
    // Attempt match precedence: friendly -> advertised -> base.
    let friendlyMatches = peers.discoveredPeers.filter { peers.peerFriendlyNames[$0.displayName] == peerName }
    let advertisedMatches = peers.discoveredPeers.filter { peers.discoveryAdvertisedNames[$0.displayName] == peerName }
    let baseMatches = peers.discoveredPeers.filter { Self.baseName(from: $0.displayName) == peerName }

    // If not found in filtered discovered set (because this device is the larger composite and stays passive), also search allBrowsedPeers.
    let friendlyAll = peers.allBrowsedPeers.filter { peers.peerFriendlyNames[$0.displayName] == peerName }
    let advertisedAll = peers.allBrowsedPeers.filter { peers.discoveryAdvertisedNames[$0.displayName] == peerName }
    let baseAll = peers.allBrowsedPeers.filter { Self.baseName(from: $0.displayName) == peerName }

    let combined = (friendlyMatches + advertisedMatches + friendlyAll + advertisedAll + baseMatches + baseAll)
      .sorted { $0.displayName < $1.displayName }

    if let target = combined.first {
      print("[JOIN] Inviting peerName=\(peerName) composite=\(target.displayName)")
      peers.invite(target)
    } else {
      print("[JOIN] No peer matched selection peerName=\(peerName). discovered=\(peers.discoveredPeers.map{ $0.displayName }) all=\(peers.allBrowsedPeers.map{ $0.displayName })")
    }
  }

  func host() {
    peers.startHosting()
    myColor = .white
    sendHello()
  }

  func join() {
    peers.join()
    myColor = .black
    sendHello()
  }

  func disconnect() {
    peers.stop()
    capturedByMe.removeAll()
    capturedByOpponent.removeAll()
    awaitingResetConfirmation = false
    incomingResetRequest = false
    movesMade = 0
  }

  // Update local player name (optional). Broadcast updated hello if connected.
  func updatePlayerName(_ newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return }
    guard trimmed != playerName else { return }
    playerName = trimmed
    storedPlayerName = trimmed
    // Only propagate to Multipeer layer if networking has been approved (else defer until approval).
    if networkingApproved {
      peers.updateAdvertisedName(trimmed)
      if peers.isConnected { sendHello(force: true) }
    } else {
      print("[VM] Deferred advertising name update until networking approved -> \(trimmed)")
    }
  }

  /// Called when user explicitly approves networking (e.g. taps Continue on intro overlay).
  func approveNetworkingAndStartIfNeeded() {
    guard !networkingApproved else { return }
    networkingApproved = true
    hasSeenNetworkPermissionIntro = true
    showNetworkPermissionIntro = false
    // Begin advertising/browsing now; this is the first point iOS may show the Local Network permission alert.
    peers.updateAdvertisedName(playerName)
    peers.startAuto()
    print("[VM] User approved networking; started auto mode")
  scheduleLocalNetworkPermissionHeuristic()
  }

  private func sendHello(force: Bool = false) {
    if force { hasSentHello = false }
    peers.send(.init(kind: .hello, move: nil, color: myColor, deviceName: playerName))
  }
}

// (Implementation split into multiple extension files: see GameViewModel+*.swift)
// MARK: - Persistence
