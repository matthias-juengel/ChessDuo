//
//  GameViewModel.swift
//
//  Created by Matthias Jüngel on 10.08.25.
//

import Foundation
import Combine
import SwiftUI

final class GameViewModel: ObservableObject {
  @Published private(set) var engine = ChessEngine()
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
  private var pendingGameToLoad: FamousGame? = nil // locally selected game awaiting acceptance
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
  @Published private(set) var boardSnapshots: [Board] = []
  // Remote history view sync
  @Published var remoteIsDrivingHistoryView: Bool = false // true while we reflect a peer's slider movement
  private var suppressHistoryViewBroadcast = false
  // Tracks whether any live moves have been made since last reset or famous game load
  private var sessionProgressed: Bool = false

  // Cache for legal destination queries: key = (boardSignature, originSquare)
  private var legalDestCache: [String: Set<Square>] = [:]
  private var lastCacheBoardSignature: String? = nil

  // Baseline (initial) board & side for current session (handles FEN starts for famous games)
  private var baselineBoard: Board = Board.initial()
  // Baseline piece counts per color/type (used to compute captures for history & FEN starts)
  private var baselineCounts: [PieceColor: [PieceType:Int]] = [.white: [:], .black: [:]]
  private var baselineSideToMove: PieceColor = .white

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
  private func pieceCounts(on board: Board) -> [PieceColor: [PieceType:Int]] {
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
  private func missingComparedToBaseline(current: Board) -> (whiteMissing: [PieceType:Int], blackMissing: [PieceType:Int]) {
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
  private func rebuildCapturedLists(for board: Board) {
    let (whiteMissing, blackMissing) = missingComparedToBaseline(current: board)
    let perspective: PieceColor = myColor ?? preferredPerspective
    let myOppColor: PieceColor = (perspective == .white) ? .black : .white
    let myColorLocal: PieceColor = perspective

    func buildList(for color: PieceColor, missing: [PieceType:Int]) -> [Piece] {
      var arr: [Piece] = []
      for t in [PieceType.queen, .rook, .bishop, .knight, .pawn] { // König wird nie geschlagen
        for _ in 0..<(missing[t] ?? 0) { arr.append(Piece(type: t, color: color)) }
      }
      return arr
    }

    let oppMissing = (myOppColor == .white) ? whiteMissing : blackMissing
    let mineMissing = (myColorLocal == .white) ? whiteMissing : blackMissing

    capturedByMe = buildList(for: myOppColor, missing: oppMissing)
    capturedByOpponent = buildList(for: myColorLocal, missing: mineMissing)
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

  var gameIsOver: Bool {
    let currentPlayerOutcome = outcomeForSide(engine.sideToMove)
    print("Current player (\(engine.sideToMove)) outcome:", currentPlayerOutcome)
    return currentPlayerOutcome != .ongoing
  }

  func outcomeForSide(_ side: PieceColor) -> GameOutcome {
    let isMate = engine.isCheckmate(for: side)
    let isStale = engine.isStalemate(for: side)
    let isRep = engine.isThreefoldRepetition()

    if isMate { return .loss }
    else if isStale { return .draw }
    else if isRep { return .draw }

    let otherSide = side == .white ? PieceColor.black : PieceColor.white

    if engine.isCheckmate(for: otherSide) {
      return .win
    } else {
      return .ongoing
    }
  }

  let peers = PeerService()
  private var cancellables: Set<AnyCancellable> = []
  private var hasSentHello = false
  private var pendingInvitationDecision: ((Bool)->Void)? = nil
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
  loadGameIfAvailable()
  // Restore myColor from persistent storage if moves have been made and value exists
  if movesMade > 0, let stored = PieceColor(rawValue: persistedMyColorRaw), myColor == nil {
    myColor = stored
  }
  // Falls beim Laden (z.B. V1 ohne History) keine Snapshots erzeugt wurden, initialisieren wir minimal.
  if boardSnapshots.isEmpty { boardSnapshots = [engine.board] }
    baselineBoard = engine.board
    baselineSideToMove = engine.sideToMove
  baselineCounts = pieceCounts(on: baselineBoard)
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

  func resetGame() {
    if peers.isConnected {
      // Connected mode: handshake reset
      if movesMade == 0 {
        performLocalReset(send: true)
      } else {
        awaitingResetConfirmation = true
        incomingResetRequest = false // ensure only one alert
        peers.send(.init(kind: .requestReset))
      }
    } else {
      // Single-device mode: show alert confirmation (no network messages)
      if movesMade == 0 {
        performLocalReset(send: false)
      } else {
        offlineResetPrompt = true
      }
    }
  }

  @discardableResult
  func makeMove(from: Square, to: Square) -> Bool {
    guard !gameIsOver else { return false }
    guard let me = myColor, engine.sideToMove == me else { return false }
    if isLegalPromotionMove(from: from, to: to) {
      pendingPromotionMove = Move(from: from, to: to, promotion: nil)
      showingPromotionPicker = true
      return true // treat as handled for drag success (engine move committed after selection)
    }
    let move = Move(from: from, to: to)
  let capturedBefore = capturedPieceConsideringEnPassant(from: from, to: to, board: engine.board)
    if engine.tryMakeMove(move) {
      withAnimation(.easeInOut(duration: 0.35)) {
        peers.send(.init(kind: .move, move: move))
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = true } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = move
        moveHistory.append(move)
        historyIndex = nil
        boardSnapshots.append(engine.board)
        saveGame()
        rebuildCapturedLists(for: engine.board)
      }
      return true
    }
    return false
  }

  /// Local move for single-device mode (no network); both colors playable
  @discardableResult
  func makeLocalMove(from: Square, to: Square) -> Bool {
    guard !gameIsOver else { return false }
    if isLegalPromotionMove(from: from, to: to) {
      pendingPromotionMove = Move(from: from, to: to, promotion: nil)
      showingPromotionPicker = true
      return true
    }
    let move = Move(from: from, to: to)
    let moverColor = engine.sideToMove
  let capturedBefore = capturedPieceConsideringEnPassant(from: from, to: to, board: engine.board)
    if engine.tryMakeMove(move) {
      withAnimation(.easeInOut(duration: 0.35)) {
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = (moverColor == .white) } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = move
        moveHistory.append(move)
        historyIndex = nil
        boardSnapshots.append(engine.board)
        saveGame()
        rebuildCapturedLists(for: engine.board)
      }
      return true
    }
    return false
  }

  private func handle(_ msg: NetMessage) {
    switch msg.kind {
    case .hello:
      // If the incoming hello carries a color and we have none yet (joining mid offline game), adopt the opposite immediately.
      if myColor == nil, let remoteColor = msg.color {
        myColor = remoteColor.opposite
        // Let remote know we accepted its implicit role claim.
        peers.send(.init(kind: .acceptRole))
      } else if let mine = myColor, let remoteColor = msg.color, mine == remoteColor {
        // Conflict: both sides think they are the same color. If we have movesMade>0 we claim white and re-propose; otherwise relinquish.
        if movesMade > 0, mine == .white {
          peers.send(.init(kind: .proposeRole))
        } else if mine == .white {
          // No local progress yet; yield white to remote.
          myColor = .black
          peers.send(.init(kind: .acceptRole))
        }
      } else {
        attemptRoleProposalIfNeeded()
      }
      requestSync()
    case .reset:
      engine.reset()
      capturedByMe.removeAll()
      capturedByOpponent.removeAll()
      movesMade = 0
      awaitingResetConfirmation = false
      incomingResetRequest = false
      lastMove = nil
      lastCapturedPieceID = nil
      lastCaptureByMe = nil
    case .move:
      if let m = msg.move {
  let capturedBefore = capturedPieceConsideringEnPassant(from: m.from, to: m.to, board: engine.board)
        if !gameIsOver, engine.tryMakeMove(m) {
          withAnimation(.easeInOut(duration: 0.35)) {
            if let cap = capturedBefore {
              lastCapturedPieceID = cap.id
              if let my = myColor { lastCaptureByMe = (cap.color != my) } else { lastCaptureByMe = (cap.color == .black) }
            } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
            movesMade += 1
            sessionProgressed = true
            lastMove = m
            moveHistory.append(m)
            historyIndex = nil
            boardSnapshots.append(engine.board)
            saveGame()
            rebuildCapturedLists(for: engine.board)
            // If it's now my turn after applying opponent's move, emit a subtle haptic.
            if peers.isConnected, let mine = myColor, engine.sideToMove == mine {
              Haptics.trigger(.moveNowMyTurn)
            }
          }
        }
      }
    case .proposeRole:
      // Other peer proposes it is white; accept if we don't have a color yet.
      if myColor == nil {
        myColor = .black
        peers.send(.init(kind: .acceptRole))
      } else if myColor == .white && movesMade == 0 {
        // Fresh session, we can still yield white if we haven't progressed.
        myColor = .black
        peers.send(.init(kind: .acceptRole))
      } // else keep current color (e.g., we have offline progress as white)
    case .acceptRole:
      // Other peer accepted our proposal, we should already have set our color.
      if myColor == nil { myColor = .white }
    case .requestReset:
      // Show incoming request; cancel any outgoing waiting state
      incomingResetRequest = true
      awaitingResetConfirmation = false
    case .acceptReset:
      performLocalReset(send: true)
    case .declineReset:
      awaitingResetConfirmation = false
      incomingResetRequest = false
    case .syncRequest:
      sendSnapshot()
    case .syncState:
      // Compare movesMade and adopt if remote is ahead
      if let remoteMoves = msg.movesMade, remoteMoves > movesMade,
         let b = msg.board,
         let stm = msg.sideToMove,
         let remoteCapturedBySender = msg.capturedByMe,
         let remoteCapturedByOpponent = msg.capturedByOpponent {
        // Sender's capturedByMe -> our capturedByOpponent
        engine = ChessEngine.fromSnapshot(board: b, sideToMove: stm)
        capturedByOpponent = remoteCapturedBySender
        capturedByMe = remoteCapturedByOpponent
        movesMade = remoteMoves
        // Adopt last move / capture highlighting from remote (translate perspective)
        if let from = msg.lastMoveFrom, let to = msg.lastMoveTo {
          lastMove = Move(from: from, to: to)
        } else {
          lastMove = nil
        }
        // Capture highlight: if remote lastCaptureByMe == true, then from our POV the capture was by opponent.
        if let capID = msg.lastCapturedPieceID, let bySender = msg.lastCaptureByMe {
          lastCapturedPieceID = capID
          lastCaptureByMe = !bySender // invert perspective
        } else {
          lastCapturedPieceID = nil
          lastCaptureByMe = nil
        }
        if let remoteHistory = msg.moveHistory {
          moveHistory = remoteHistory
          historyIndex = nil
          boardSnapshots = []
          rebuildSnapshotsFromHistory()
        }
//        recomputeOutcomeIfNeeded()
      } else if let remoteMoves = msg.movesMade, remoteMoves < movesMade {
        // We're ahead; send our snapshot back (echo) so peer can adopt.
        sendSnapshot()
      }
    case .colorSwap:
      // Swap colors locally if no moves made yet
      if movesMade == 0, let current = myColor { myColor = current.opposite }
    case .requestHistoryRevert:
      // Opponent asks to revert to count
      if let target = msg.revertToCount {
        incomingHistoryRevertRequest = target
        awaitingHistoryRevertConfirmation = false
        requestedHistoryRevertTarget = nil
      }
    case .acceptHistoryRevert:
      // Opponent accepted our request; perform revert locally and broadcast authoritative revertHistory
      if let target = msg.revertToCount {
        performHistoryRevert(to: target, send: true)
        awaitingHistoryRevertConfirmation = false
        requestedHistoryRevertTarget = nil
      }
    case .declineHistoryRevert:
      awaitingHistoryRevertConfirmation = false
      incomingHistoryRevertRequest = nil
      requestedHistoryRevertTarget = nil
    case .revertHistory:
      if let target = msg.revertToCount { performHistoryRevert(to: target, send: false) }
    case .historyView:
      // Peer entered or exited history view. We mirror their index unless we ourselves are currently the driver.
      if let remoteIdx = msg.historyViewIndex { // remote is in history mode
        // Enter history view only if remote index is a past state ( < moveHistory.count )
        if remoteIdx >= 0 && remoteIdx <= moveHistory.count && remoteIdx != moveHistory.count {
          suppressHistoryViewBroadcast = true
          remoteIsDrivingHistoryView = true
          historyIndex = remoteIdx
          suppressHistoryViewBroadcast = false
        }
      } else {
        // Remote returned to live view; exit if we are following
        if remoteIsDrivingHistoryView {
          suppressHistoryViewBroadcast = true
          remoteIsDrivingHistoryView = false
          historyIndex = nil
          suppressHistoryViewBroadcast = false
        }
      }
    case .requestLoadGame:
      // Opponent wants to load a famous game; show prompt only if we have progress (if no moves we can silently accept?)
      incomingLoadGameRequestTitle = msg.gameTitle
      awaitingLoadGameConfirmation = false
    case .acceptLoadGame:
      // Peer accepted our request; now send authoritative loadGameState snapshot using pendingGameToLoad
      if let game = pendingGameToLoad {
        applyFamousGame(game, broadcast: true)
        pendingGameToLoad = nil
      }
      awaitingLoadGameConfirmation = false
    case .declineLoadGame:
      awaitingLoadGameConfirmation = false
      pendingGameToLoad = nil
      incomingLoadGameRequestTitle = nil
    case .loadGameState:
      // Adopt incoming authoritative famous game snapshot
      if let b = msg.board,
         let stm = msg.sideToMove,
         let remoteMoves = msg.movesMade,
         let remoteCapturedBySender = msg.capturedByMe,
         let remoteCapturedByOpponent = msg.capturedByOpponent,
         let remoteHistory = msg.moveHistory {
        engine = ChessEngine.fromSnapshot(board: b, sideToMove: stm)
        capturedByOpponent = remoteCapturedBySender
        capturedByMe = remoteCapturedByOpponent
        movesMade = remoteMoves
        moveHistory = remoteHistory
        lastMove = msg.lastMoveFrom.flatMap { from in msg.lastMoveTo.map { Move(from: from, to: $0) } }
        lastCapturedPieceID = msg.lastCapturedPieceID
        lastCaptureByMe = msg.lastCaptureByMe.map { !$0 } // invert perspective like syncState
        historyIndex = nil
        remoteIsDrivingHistoryView = false
        boardSnapshots = []
        rebuildSnapshotsFromHistory()
        saveGame()
  sessionProgressed = false
      }
    }
  }

  /// If colors not assigned yet and exactly one peer connected, decide deterministically.
  private func attemptRoleProposalIfNeeded() {
    guard myColor == nil, let first = peers.connectedPeers.first else { return }
    // Use lexicographical comparison of display names to pick white to ensure symmetry
    let iAmWhite = peers.localDisplayName < first.displayName
    if iAmWhite {
      myColor = .white
      peers.send(.init(kind: .proposeRole))
    } else {
      // Wait to receive proposeRole; if none arrives (race), we can still fallback later.
    }
  }

  func performLocalReset(send: Bool) {
    engine.reset()
    capturedByMe.removeAll()
    capturedByOpponent.removeAll()
    movesMade = 0
    awaitingResetConfirmation = false
    incomingResetRequest = false
    offlineResetPrompt = false
//    outcome = .ongoing
    lastMove = nil
    lastCapturedPieceID = nil
    lastCaptureByMe = nil
  moveHistory = []
  historyIndex = nil
    sessionProgressed = false
  boardSnapshots = [engine.board]
    baselineBoard = engine.board
    baselineSideToMove = engine.sideToMove
  baselineCounts = pieceCounts(on: baselineBoard)
  rebuildCapturedLists(for: engine.board)
    if send { peers.send(.init(kind: .reset)) }
  saveGame()
  }

  // MARK: - History Revert Logic
  /// Request a revert to a given move count (0...movesMade). In connected mode triggers confirmation; offline directly reverts.
  func requestHistoryRevert(to target: Int) {
    guard target >= 0, target <= moveHistory.count else { return }
    if peers.isConnected {
      // If we have no moves difference (target == movesMade) ignore
      if target == moveHistory.count { return }
      awaitingHistoryRevertConfirmation = true
      incomingHistoryRevertRequest = nil
  requestedHistoryRevertTarget = target
      peers.send(.init(kind: .requestHistoryRevert, revertToCount: target))
    } else {
      performHistoryRevert(to: target, send: false)
    }
  }

  /// Respond to an incoming revert request.
  func respondToHistoryRevertRequest(accept: Bool) {
    guard let target = incomingHistoryRevertRequest else { return }
    if accept {
      // Accept: send accept and perform locally after receiving authoritative revertHistory
  peers.send(.init(kind: .acceptHistoryRevert, revertToCount: target))
    } else {
  peers.send(.init(kind: .declineHistoryRevert, revertToCount: target))
    }
    incomingHistoryRevertRequest = nil
  }

  /// Perform the actual revert, adjusting engine, history, captures etc. If send==true broadcast revertHistory.
  func performHistoryRevert(to target: Int, send: Bool) {
    guard target >= 0, target <= moveHistory.count else { return }
    // Rebuild engine from first target moves
    var e = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    var newCapturedByMe: [Piece] = []
    var newCapturedByOpponent: [Piece] = []
    var lastCapID: UUID? = nil
    var lastCapByMe: Bool? = nil
    var newLastMove: Move? = nil
    for i in 0..<target {
      let mv = moveHistory[i]
      // capture detection before applying
      let captured: Piece? = capturedPieceConsideringEnPassant(from: mv.from, to: mv.to, board: e.board)
      _ = e.tryMakeMove(mv)
      if let cap = captured {
        // Determine whose capture list it goes into (from POV of myColor if connected, else white=me assumption)
        if let my = myColor { // multiplayer perspective
          if cap.color == my { newCapturedByOpponent.append(cap); lastCapByMe = false }
          else { newCapturedByMe.append(cap); lastCapByMe = true }
        } else { // single device: white captures -> capturedByMe
          if cap.color == .black { newCapturedByMe.append(cap); lastCapByMe = true } else { newCapturedByOpponent.append(cap); lastCapByMe = false }
        }
        lastCapID = cap.id
      }
      newLastMove = mv
    }
    engine = e
    capturedByMe = newCapturedByMe
    capturedByOpponent = newCapturedByOpponent
    movesMade = target
    lastMove = newLastMove
    lastCapturedPieceID = lastCapID
    lastCaptureByMe = lastCapByMe
    // Truncate histories
  if target < moveHistory.count { moveHistory = Array(moveHistory.prefix(target)) }
  sessionProgressed = target > 0
  // Ensure all devices exit history mode after a confirmed revert.
  // Suppress broadcasting while we locally reset historyIndex to avoid redundant historyView(nil) chatter;
  // the authoritative revertHistory message (if send == true) implicitly instructs remote to rebuild and exit.
  let prevSuppress = suppressHistoryViewBroadcast
  suppressHistoryViewBroadcast = true
  historyIndex = nil
  remoteIsDrivingHistoryView = false
  suppressHistoryViewBroadcast = prevSuppress
    // Rebuild snapshots for truncated history
    boardSnapshots = [ChessEngine().board]
    var rebuildEngine = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    for mv in moveHistory { _ = rebuildEngine.tryMakeMove(mv); boardSnapshots.append(rebuildEngine.board) }
    // Persist
    saveGame()
    if send { peers.send(.init(kind: .revertHistory, revertToCount: target)) }
  lastAppliedHistoryRevertTarget = target
  awaitingHistoryRevertConfirmation = false
  incomingHistoryRevertRequest = nil
  requestedHistoryRevertTarget = nil
  rebuildCapturedLists(for: engine.board)
  }

  // MARK: - Famous Game Load Logic
  /// Entry point from UI when user selects a famous game.
  func userSelectedFamousGame(_ game: FamousGame) {
  // Require confirmation only if session has progressed (live moves since last load/reset)
  if peers.isConnected, sessionProgressed {
      pendingGameToLoad = game
      awaitingLoadGameConfirmation = true
      // Send request with game title metadata
      peers.send(.init(kind: .requestLoadGame, gameTitle: game.title))
    } else if peers.isConnected {
      // No existing moves: directly apply & broadcast snapshot
      applyFamousGame(game, broadcast: true)
    } else {
      // Offline single-device: just load locally
      applyFamousGame(game, broadcast: false)
    }
  }

  /// Respond to incoming load game request.
  func respondToLoadGameRequest(accept: Bool) {
    guard let title = incomingLoadGameRequestTitle else { return }
    if accept {
      // Accept: send accept; wait for authoritative loadGameState message.
      peers.send(.init(kind: .acceptLoadGame, gameTitle: title))
    } else {
      peers.send(.init(kind: .declineLoadGame, gameTitle: title))
    }
    incomingLoadGameRequestTitle = nil
  }

  /// Apply a famous game (optionally with an initial FEN) to local state, rebuilding baselines and history.
  /// - Parameters:
  ///   - game: FamousGame instance (moves or PGN parsed if moves empty).
  ///   - broadcast: If true, sends a `.loadGameState` message to connected peer.
  /// This is internal so tests (and future features) can load curated positions with production logic.
  func applyFamousGame(_ game: FamousGame, broadcast: Bool) {
    if let fen = game.initialFEN, let custom = ChessEngine.fromFEN(fen) {
      engine = custom
    } else {
      engine = ChessEngine()
    }
    baselineBoard = engine.board
    baselineSideToMove = engine.sideToMove
  baselineCounts = pieceCounts(on: baselineBoard)
    moveHistory = []
    boardSnapshots = [engine.board]
    capturedByMe = []
    capturedByOpponent = []
  movesMade = 0
  sessionProgressed = false
    lastMove = nil
    lastCapturedPieceID = nil
    lastCaptureByMe = nil
    historyIndex = nil
    remoteIsDrivingHistoryView = false

    var sourceMoves: [Move] = game.moves
    if sourceMoves.isEmpty, let pgn = game.pgn {
      if case .success(let parsed) = PGNParser.parseMoves(pgn: pgn) { sourceMoves = parsed }
    }
    for mv in sourceMoves {
      let capturedBefore = capturedPieceConsideringEnPassant(from: mv.from, to: mv.to, board: engine.board)
      if engine.tryMakeMove(mv) {
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = (cap.color == .black) } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        moveHistory.append(mv)
        boardSnapshots.append(engine.board)
        movesMade += 1
        lastMove = mv
      } else { break }
    }
    saveGame()
  rebuildCapturedLists(for: engine.board)
    if broadcast {
      let msg = NetMessage(kind: .loadGameState,
                           move: nil,
                           color: nil,
                           deviceName: playerName,
                           board: engine.board,
                           sideToMove: engine.sideToMove,
                           movesMade: movesMade,
                           capturedByMe: capturedByMe,
                           capturedByOpponent: capturedByOpponent,
                           lastMoveFrom: lastMove?.from,
                           lastMoveTo: lastMove?.to,
                           lastCapturedPieceID: lastCapturedPieceID,
                           lastCaptureByMe: lastCaptureByMe,
                           moveHistory: moveHistory,
                           historyViewIndex: nil,
                           gameTitle: game.title)
      peers.send(msg)
    }
  }

  /// Utility for UI to be called (e.g. via onReceive) to clear history view when revert applied.
  func acknowledgeAppliedHistoryRevert() {
    // No-op placeholder for future if additional side effects needed.
  }

  func respondToResetRequest(accept: Bool) {
    if accept {
      peers.send(.init(kind: .acceptReset))
      performLocalReset(send: true)
    } else {
      peers.send(.init(kind: .declineReset))
  // If we were the requester, clear our awaiting flag; if we were the recipient, clear incoming flag.
  incomingResetRequest = false
  awaitingResetConfirmation = false
    }
  }

  /// Cancel an outgoing history revert request (sends a decline so opponent dismisses their dialog)
  func cancelPendingHistoryRevertRequest() {
    guard awaitingHistoryRevertConfirmation, let target = requestedHistoryRevertTarget else { return }
    awaitingHistoryRevertConfirmation = false
    peers.send(.init(kind: .declineHistoryRevert, revertToCount: target))
    requestedHistoryRevertTarget = nil
  }

  func respondToIncomingInvitation(_ accept: Bool) {
    pendingInvitationDecision?(accept)
    pendingInvitationDecision = nil
    incomingJoinRequestPeer = nil
  }

  // Host (white) can swap colors before any move has been made.
  func swapColorsIfAllowed() {
    guard movesMade == 0, let me = myColor else { return }
    // Only allow the current white to initiate swap (to avoid race)
    guard me == .white else { return }
    myColor = .black
    peers.send(.init(kind: .colorSwap))
  // Also update preferred perspective so if we later disconnect we retain orientation.
  preferredPerspective = .black
  }

  private func requestSync() {
    peers.send(.init(kind: .syncRequest))
  }

  private func sendSnapshot() {
    let msg = NetMessage(kind: .syncState,
                         move: nil,
                         color: nil,
                         deviceName: playerName,
                         board: engine.board,
                         sideToMove: engine.sideToMove,
                         movesMade: movesMade,
                         capturedByMe: capturedByMe,
                         capturedByOpponent: capturedByOpponent,
                         lastMoveFrom: lastMove?.from,
                         lastMoveTo: lastMove?.to,
                         lastCapturedPieceID: lastCapturedPieceID,
                         lastCaptureByMe: lastCaptureByMe,
                         moveHistory: moveHistory)
    peers.send(msg)
  }

  // Determine if a move from->to is a promotion (pawn reaching last rank)
  private func isPromotionMove(from: Square, to: Square) -> Bool {
    guard let piece = engine.board.piece(at: from) else { return false }
    guard piece.type == .pawn else { return false }
    if piece.color == .white && to.rank == 7 { return true }
    if piece.color == .black && to.rank == 0 { return true }
    return false
  }

  // Full legality check for promotion attempts: ensure the move would succeed (aside from promotion choice)
  private func isLegalPromotionMove(from: Square, to: Square) -> Bool {
    guard isPromotionMove(from: from, to: to) else { return false }
    // Try move on a copy with default queen promotion; if engine accepts it's legal
    var copy = engine
    let test = Move(from: from, to: to, promotion: .queen)
    return copy.tryMakeMove(test)
  }

  // Detect en-passant captured pawn before engine.tryMakeMove mutates board.
  private func capturedPieceConsideringEnPassant(from: Square, to: Square, board: Board) -> Piece? {
    if let mover = board.piece(at: from), mover.type == .pawn {
      let df = abs(to.file - from.file)
      if df == 1, to.rank != from.rank, board.piece(at: to) == nil { // diagonal move to empty square
        // En passant: captured pawn is behind destination (opposite direction of mover)
        let dir = (mover.color == .white) ? 1 : -1
        let capturedSq = Square(file: to.file, rank: to.rank - dir)
        if let cap = board.piece(at: capturedSq), cap.type == .pawn, cap.color != mover.color { return cap }
      }
    }
    return board.piece(at: to)
  }

  // Finalize promotion selection
  func promote(to pieceType: PieceType) {
    guard var base = pendingPromotionMove else { return }
    base = Move(from: base.from, to: base.to, promotion: pieceType)
    let capturedBefore = engine.board.piece(at: base.to)
    if engine.tryMakeMove(base) {
      withAnimation(.easeInOut(duration: 0.35)) {
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = (myColor == engine.sideToMove.opposite) } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        movesMade += 1
        sessionProgressed = true
        lastMove = base
        if peers.isConnected { peers.send(.init(kind: .move, move: base)) }
        moveHistory.append(base)
        historyIndex = nil
        boardSnapshots.append(engine.board)
        saveGame()
        rebuildCapturedLists(for: engine.board)
      }
    }
    pendingPromotionMove = nil
    showingPromotionPicker = false
  }

  func cancelPromotion() {
    pendingPromotionMove = nil
    showingPromotionPicker = false
  }
}


// MARK: - Persistence
extension GameViewModel {
  struct GamePersistedV1: Codable { // legacy without moveHistory
    let version: Int
    let engine: ChessEngine
    let myColor: PieceColor?
    let capturedByMe: [Piece]
    let capturedByOpponent: [Piece]
    let movesMade: Int
    let lastMove: Move?
    let lastCapturedPieceID: UUID?
    let lastCaptureByMe: Bool?
  }
  struct GamePersistedV2: Codable { // adds moveHistory
    let version: Int
    let engine: ChessEngine
    let myColor: PieceColor?
    let capturedByMe: [Piece]
    let capturedByOpponent: [Piece]
    let movesMade: Int
    let lastMove: Move?
    let lastCapturedPieceID: UUID?
    let lastCaptureByMe: Bool?
    let moveHistory: [Move]
  }

  var saveURL: URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("ChessDuo", isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir.appendingPathComponent("game.json")
  }

  func saveGame() {
  let snapshot = GamePersistedV2(version: 2,
                   engine: engine,
                   myColor: myColor,
                   capturedByMe: capturedByMe,
                   capturedByOpponent: capturedByOpponent,
                   movesMade: movesMade,
                   lastMove: lastMove,
                   lastCapturedPieceID: lastCapturedPieceID,
                   lastCaptureByMe: lastCaptureByMe,
                   moveHistory: moveHistory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    do {
      let data = try encoder.encode(snapshot)
      let tmp = saveURL.appendingPathExtension("tmp")
      try data.write(to: tmp, options: .atomic)
      // Atomic replace
      try? FileManager.default.removeItem(at: saveURL)
      try FileManager.default.moveItem(at: tmp, to: saveURL)
    } catch {
      // Silent fail; could add logging
      print("Save failed", error)
    }
  }

  func loadGameIfAvailable() {
    let url = saveURL
    guard let data = try? Data(contentsOf: url) else { return }
    let decoder = JSONDecoder()
    if let v2 = try? decoder.decode(GamePersistedV2.self, from: data) {
      engine = v2.engine
      myColor = v2.myColor
      capturedByMe = v2.capturedByMe
      capturedByOpponent = v2.capturedByOpponent
      movesMade = v2.movesMade
      lastMove = v2.lastMove
      lastCapturedPieceID = v2.lastCapturedPieceID
      lastCaptureByMe = v2.lastCaptureByMe
      moveHistory = v2.moveHistory
      // We'll rebuild snapshots below (including initial) to preserve stable piece identity for animations
      boardSnapshots = []
    } else if let v1 = try? decoder.decode(GamePersistedV1.self, from: data) {
      engine = v1.engine
      myColor = v1.myColor
      capturedByMe = v1.capturedByMe
      capturedByOpponent = v1.capturedByOpponent
      movesMade = v1.movesMade
      lastMove = v1.lastMove
      lastCapturedPieceID = v1.lastCapturedPieceID
      lastCaptureByMe = v1.lastCaptureByMe
      moveHistory = []
      // Rebuild snapshots from engine current board only (no move history available in V1)
      boardSnapshots = []
    }
    // After loading any version, rebuild snapshots to enable history animations.
    rebuildSnapshotsFromHistory()
  // Align preferred perspective with current multiplayer color if connected previously
  if let mine = myColor { preferredPerspective = mine }
    sessionProgressed = movesMade > 0
  }

  // Reconstruct a board state after n moves from history (n in 0...moveHistory.count)
  func boardAfterMoves(_ n: Int) -> Board {
  if n < boardSnapshots.count { return boardSnapshots[n] }
  if n == moveHistory.count { return engine.board }
  var e = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
  for i in 0..<min(n, moveHistory.count) { _ = e.tryMakeMove(moveHistory[i]) }
  return e.board
  }

  var displayedBoard: Board { historyIndex.map { boardAfterMoves($0) } ?? engine.board }
  var inHistoryView: Bool { historyIndex != nil }

  // Get the side to move for the displayed board (historical or current)
  var displayedSideToMove: PieceColor {
    guard let idx = historyIndex else { return engine.sideToMove }
    // Side to move alternates with each move, starting with white
    return (idx % 2 == 0) ? .white : .black
  }

  // Check if the current side is in check on the displayed board
  func isDisplayedSideInCheck() -> Bool {
    let board = displayedBoard
    let sideToMove = displayedSideToMove

    // Create a temporary engine to use the check detection methods
    let tempEngine = ChessEngine.fromSnapshot(board: board, sideToMove: sideToMove)
    return tempEngine.isInCheck(sideToMove)
  }

  // Check if the current side is checkmated on the displayed board
  func isDisplayedSideCheckmated() -> Bool {
    let board = displayedBoard
    let sideToMove = displayedSideToMove

    // Create a temporary engine to use the checkmate detection methods
    let tempEngine = ChessEngine.fromSnapshot(board: board, sideToMove: sideToMove)
    return tempEngine.isCheckmate(for: sideToMove)
  }

  // Get the game outcome for the displayed board (historical or current)
  func displayedOutcomeForSide(_ side: PieceColor) -> GameOutcome {
    // If we're not in history view, use the current outcome
    guard historyIndex != nil else { return outcomeForSide(side) }

    let board = displayedBoard
    let sideToMove = displayedSideToMove

    // Create a temporary engine to use the outcome detection methods
    let tempEngine = ChessEngine.fromSnapshot(board: board, sideToMove: sideToMove)

    let isMate = tempEngine.isCheckmate(for: side)
    let isStale = tempEngine.isStalemate(for: side)
    // Note: threefold repetition is complex for historical positions, so we skip it in history view

    if isMate { return .loss }
    else if isStale { return .draw }

    let otherSide = side == .white ? PieceColor.black : PieceColor.white

    if tempEngine.isCheckmate(for: otherSide) {
      return .win
    } else {
      return .ongoing
    }
  }

  // Calculate point advantage based on captured pieces
  func pointAdvantage(forMe: Bool) -> Int {
    let myPieces = capturedByMe
    let opponentPieces = capturedByOpponent

    let myPoints = myPieces.reduce(0) { $0 + pieceValue($1) }
    let opponentPoints = opponentPieces.reduce(0) { $0 + pieceValue($1) }

    return forMe ? (myPoints - opponentPoints) : (opponentPoints - myPoints)
  }

  // Calculate point advantage for historical positions
  func historicalPointAdvantage(forMe: Bool) -> Int {
    guard let idx = historyIndex else { return pointAdvantage(forMe: forMe) }
    let board = boardAfterMoves(idx)
    // Derive missing piece counts from baseline -> captured pieces for each side
    let (whiteMissing, blackMissing) = missingComparedToBaseline(current: board)
    func points(from missing: [PieceType:Int]) -> Int {
      missing.reduce(0) { partial, kv in
        let (type, count) = kv
        let value: Int
        switch type { case .queen: value = 9; case .rook: value = 5; case .bishop, .knight: value = 3; case .pawn: value = 1; case .king: value = 0 }
        return partial + value * count
      }
    }
    // whiteMissing are pieces captured BY black; blackMissing -> captured by white.
    let whiteCapturedPoints = points(from: blackMissing) // points white has taken (black's missing pieces)
    let blackCapturedPoints = points(from: whiteMissing)
    if let my = myColor { // multiplayer perspective
      let myPts = (my == .white) ? whiteCapturedPoints : blackCapturedPoints
      let oppPts = (my == .white) ? blackCapturedPoints : whiteCapturedPoints
      return forMe ? (myPts - oppPts) : (oppPts - myPts)
    } else { // single-device: bottom assumed white for 'forMe'
      let myPts = forMe ? whiteCapturedPoints : blackCapturedPoints
      let oppPts = forMe ? blackCapturedPoints : whiteCapturedPoints
      return (myPts - oppPts)
    }
  }

  private func pieceValue(_ piece: Piece) -> Int {
    switch piece.type {
    case .queen: return 9
    case .rook: return 5
    case .bishop, .knight: return 3
    case .pawn: return 1
    case .king: return 0 // should not normally appear
    }
  }
}

// MARK: - Legal Move Query (UI helpers)
extension GameViewModel {
  /// Returns the set of legal destination squares for a piece on `from` in the current live position.
  /// If history view is active or no piece / wrong color, returns empty set.
  func legalDestinations(from: Square) -> Set<Square> {
    if historyIndex != nil { return [] }
    guard let piece = engine.board.piece(at: from) else { return [] }
    if peers.isConnected, let mine = myColor, engine.sideToMove != mine { return [] }
    if piece.color != engine.sideToMove { return [] }
    let sig = boardSignature()
    if lastCacheBoardSignature != sig { // board changed -> clear cache
      legalDestCache.removeAll()
      lastCacheBoardSignature = sig
    }
    let cacheKey = sig + "|f" + String(from.file) + "r" + String(from.rank)
    if let cached = legalDestCache[cacheKey] { return cached }
    let moves = engine.generateLegalMoves(for: engine.sideToMove)
    let dests = Set(moves.filter { $0.from == from }.map { $0.to })
    legalDestCache[cacheKey] = dests
    return dests
  }

  // Load a famous game - replaces current game state
  func loadFamousGame(_ game: FamousGame) {
    // Reset to initial state
    engine = ChessEngine()
    moveHistory = []
    boardSnapshots = [engine.board] // Initial position
    capturedByMe = []
    capturedByOpponent = []
    movesMade = 0
    lastMove = nil
    lastCapturedPieceID = nil
    lastCaptureByMe = nil
    historyIndex = nil
  baselineBoard = engine.board
  baselineSideToMove = engine.sideToMove
  baselineCounts = pieceCounts(on: baselineBoard)

    // Determine source of moves: explicit array or PGN parsing fallback
    var sourceMoves: [Move] = game.moves
    if sourceMoves.isEmpty, let pgn = game.pgn {
      switch PGNParser.parseMoves(pgn: pgn) {
      case .success(let parsed): sourceMoves = parsed
      case .failure(let err):
        print("PGN parse failed for game \(game.title): \(err)")
      }
    }

    // Apply all moves from the famous game (array or parsed PGN)
    for move in sourceMoves {
      let capturedBefore = capturedPieceConsideringEnPassant(from: move.from, to: move.to, board: engine.board)
      if engine.tryMakeMove(move) {
        if let cap = capturedBefore { lastCapturedPieceID = cap.id; lastCaptureByMe = (cap.color == .black) } else { lastCapturedPieceID = nil; lastCaptureByMe = nil }
        moveHistory.append(move)
        boardSnapshots.append(engine.board)
        movesMade += 1
        lastMove = move
      } else {
        print("Skipped illegal famous game move from (f:\(move.from.file) r:\(move.from.rank)) to (f:\(move.to.file) r:\(move.to.rank))")
        break
      }
    }
    rebuildCapturedLists(for: engine.board)
  // Keep historyIndex nil so UI displays live board
  rebuildCapturedLists(for: engine.board)
  saveGame()
  }
}

// MARK: - Board Signature (for legal move cache invalidation)
private extension GameViewModel {
  /// Lightweight signature representing current board layout + side to move.
  /// Not a full Zobrist hash; sufficient to know when any piece configuration changes.
  func boardSignature() -> String {
    var s = String(); s.reserveCapacity(8*8*2 + 1)
    for rank in 0..<8 {
      for file in 0..<8 {
        let sq = Square(file: file, rank: rank)
        if let p = engine.board.piece(at: sq) {
          // Color letter + piece type first char
            let c = (p.color == .white ? "W" : "B")
            let t = String(p.type.rawValue.first!)
            s.append(c); s.append(t)
        } else {
          s.append("__")
        }
      }
    }
    s.append(engine.sideToMove == .white ? "w" : "b")
    return s
  }
}

private extension GameViewModel {
  var isSingleDeviceMode: Bool { !peers.isConnected }
  static func baseName(from composite: String) -> String {
    // Split at first '#' only; if absent return full string
    if let idx = composite.firstIndex(of: "#") {
      return String(composite[..<idx])
    }
    return composite
  }
}

extension GameViewModel {
  // For a given historyIndex (non-nil, 1...moveHistory.count) return the piece id captured on the PREVIOUS move (the move that produced this position),
  // and whether it was captured by me (from myColor perspective / or white in single-device when myColor == nil).
  func historicalCaptureHighlight(at historyIndex: Int) -> (pieceID: UUID, byMe: Bool)? {
    // historyIndex represents board AFTER that many moves. So the last applied move is moveHistory[historyIndex-1].
    guard historyIndex > 0, historyIndex <= moveHistory.count else { return nil }
  var engine = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    // Play moves up to before the last one to inspect capture result.
    for i in 0..<(historyIndex - 1) { _ = engine.tryMakeMove(moveHistory[i]) }
    let move = moveHistory[historyIndex - 1]
    // Determine captured piece of that move similar to live logic (includes en passant)
    let captured: Piece? = {
      // Normal capture: piece on destination in pre-move board
      if let piece = engine.board.piece(at: move.to) { return piece }
      // En passant possibility
      if let moving = engine.board.piece(at: move.from), moving.type == .pawn, move.from.file != move.to.file, engine.board.piece(at: move.to) == nil {
        let dir = moving.color == .white ? 1 : -1
        let capturedSq = Square(file: move.to.file, rank: move.to.rank - dir)
        if let epPawn = engine.board.piece(at: capturedSq), epPawn.color != moving.color, epPawn.type == .pawn { return epPawn }
      }
      return nil
    }()
    // Apply the move to advance engine (not strictly needed for highlight decision)
    _ = engine.tryMakeMove(move)
    guard let cap = captured else { return nil }
    let capturedByWhite = cap.color == .black // if black piece captured -> by white
    let byMe: Bool = {
      if let my = myColor { return (my == .white) == capturedByWhite } // if my color white and capture by white -> byMe
      // single-device: bottom (capturedByMe list) corresponds to white's captures
      return capturedByWhite
    }()
    return (cap.id, byMe)
  }
}

// MARK: - Snapshot Rebuild
private extension GameViewModel {
  /// Rebuild `boardSnapshots` from `moveHistory` ensuring stable Piece.id continuity between successive boards.
  /// This should be called after loading persisted state or if snapshots are detected incomplete.
  func rebuildSnapshotsFromHistory() {
    if boardSnapshots.count == moveHistory.count + 1 { return }
    var e = ChessEngine.fromSnapshot(board: baselineBoard, sideToMove: baselineSideToMove)
    var newSnapshots: [Board] = [baselineBoard]
    for mv in moveHistory { _ = e.tryMakeMove(mv); newSnapshots.append(e.board) }
    if let last = newSnapshots.last, !boardsEqual(last, engine.board) {
      engine = ChessEngine.fromSnapshot(board: last, sideToMove: (moveHistory.count % 2 == 0) ? baselineSideToMove : baselineSideToMove.opposite)
    }
    boardSnapshots = newSnapshots
  }

  /// Lightweight board equality (piece type & color at each square)
  private func boardsEqual(_ a: Board, _ b: Board) -> Bool {
    for rank in 0..<8 { for file in 0..<8 { let sq = Square(file: file, rank: rank); let pa = a.piece(at: sq); let pb = b.piece(at: sq); if pa?.type != pb?.type || pa?.color != pb?.color { return false } } }
    return true
  }
}
