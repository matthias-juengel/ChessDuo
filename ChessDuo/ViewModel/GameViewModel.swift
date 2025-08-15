//
//  GameViewModel.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import Foundation
import Combine
import SwiftUI

final class GameViewModel: ObservableObject {
  @Published private(set) var engine = ChessEngine()
  @Published var myColor: PieceColor? = nil
  @Published var otherDeviceNames: [String] = []
  @Published var discoveredPeerNames: [String] = [] // for UI prompt (friendly names without unique suffix)
  @Published var capturedByMe: [Piece] = []
  @Published var capturedByOpponent: [Piece] = []
  @Published var movesMade: Int = 0
  @Published var awaitingResetConfirmation: Bool = false
  @Published var incomingResetRequest: Bool = false
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

  // Export current game state as a textual snapshot (for debugging / tests)
  func exportText() -> String {
    // Ensure status is up to date before exporting (fallback safety)
//    recomputeOutcomeIfNeeded()
    var lines: [String] = []
    lines.append("ChessDuoExport v1")
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

  init() {
  // Attempt to load persisted game before starting networking so board state is restored.
  loadGameIfAvailable()
  // Falls beim Laden (z.B. V1 ohne History) keine Snapshots erzeugt wurden, initialisieren wir minimal.
  if boardSnapshots.isEmpty { boardSnapshots = [engine.board] }
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
      .combineLatest(peers.$peerFriendlyNames)
      .map { peerIDs, friendlyMap in
        peerIDs.map { peer in
          if let friendly = friendlyMap[peer.displayName] { return friendly }
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
          if !self.hasSentHello { self.sendHello(); self.hasSentHello = true }
          self.attemptRoleProposalIfNeeded()
          // Initiate state sync (both sides may request; reconciliation chooses higher move count)
          self.requestSync()
        } else {
          // Reset when all peers gone so a new connection can renegotiate.
          self.myColor = nil
          self.hasSentHello = false
        }
      }
      .store(in: &cancellables)

    // Mirror discovered peers to names for confirmation UI (strip suffix)
    peers.$discoveredPeers
      .map { $0.map { Self.baseName(from: $0.displayName) }.sorted() }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] names in self?.discoveredPeerNames = names }
      .store(in: &cancellables)

    // Automatically start symmetric discovery
    peers.startAuto()
  }

  // User accepted to connect with a given peer name
  func confirmJoin(peerName: String) {
    // Match by friendly base name (since UI lists stripped names); if multiple (same friendly name on different devices) pick lexicographically smallest full display name for determinism.
    let candidates = peers.discoveredPeers.filter { Self.baseName(from: $0.displayName) == peerName }
    if let target = candidates.sorted(by: { $0.displayName < $1.displayName }).first {
      peers.invite(target)
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

  private func sendHello() {
    // Send the friendly (unsuffixed) device name
    peers.send(.init(kind: .hello, move: nil, color: myColor, deviceName: peers.localFriendlyName))
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
    let isPromotion = isPromotionMove(from: from, to: to)
    if isPromotion {
      // Defer until user picks piece
      pendingPromotionMove = Move(from: from, to: to, promotion: nil)
      showingPromotionPicker = true
      return true // treat as handled for drag success (piece will transition via picker)
    }
    let move = Move(from: from, to: to)
  let capturedBefore = capturedPieceConsideringEnPassant(from: from, to: to, board: engine.board)
    if engine.tryMakeMove(move) {
      withAnimation(.easeInOut(duration: 0.35)) {
        peers.send(.init(kind: .move, move: move))
        if let cap = capturedBefore {
          capturedByMe.append(cap)
          lastCapturedPieceID = cap.id
          lastCaptureByMe = true
        } else {
          lastCapturedPieceID = nil
          lastCaptureByMe = nil
        }
        movesMade += 1
        lastMove = move
  moveHistory.append(move)
  historyIndex = nil
  boardSnapshots.append(engine.board)
  saveGame()
      }
      return true
    }
    return false
  }

  /// Local move for single-device mode (no network); both colors playable
  @discardableResult
  func makeLocalMove(from: Square, to: Square) -> Bool {
    guard !gameIsOver else { return false }
    let isPromotion = isPromotionMove(from: from, to: to)
    if isPromotion {
      pendingPromotionMove = Move(from: from, to: to, promotion: nil)
      showingPromotionPicker = true
      return true
    }
    let move = Move(from: from, to: to)
    let moverColor = engine.sideToMove
  let capturedBefore = capturedPieceConsideringEnPassant(from: from, to: to, board: engine.board)
    if engine.tryMakeMove(move) {
      withAnimation(.easeInOut(duration: 0.35)) {
        if let cap = capturedBefore {
          // Attribute capture list based on mover color (white = my side list if we treat white bottom)
          if moverColor == .white {
            capturedByMe.append(cap)
            lastCaptureByMe = true
          } else {
            capturedByOpponent.append(cap)
            lastCaptureByMe = false
          }
          lastCapturedPieceID = cap.id
        } else {
          lastCapturedPieceID = nil
          lastCaptureByMe = nil
        }
        movesMade += 1
        lastMove = move
  moveHistory.append(move)
  historyIndex = nil
  boardSnapshots.append(engine.board)
  saveGame()
      }
      return true
    }
    return false
  }

  private func handle(_ msg: NetMessage) {
    switch msg.kind {
    case .hello:
      attemptRoleProposalIfNeeded()
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
            if let cap = capturedBefore, cap.color == myColor {
              capturedByOpponent.append(cap)
              lastCapturedPieceID = cap.id
              lastCaptureByMe = false
            } else if let cap = capturedBefore {
              lastCapturedPieceID = cap.id
              lastCaptureByMe = true
            } else {
              lastCapturedPieceID = nil
              lastCaptureByMe = nil
            }
            movesMade += 1
            lastMove = m
            moveHistory.append(m)
            historyIndex = nil
            boardSnapshots.append(engine.board)
            saveGame()
          }
        }
      }
    case .proposeRole:
      // Other peer proposes it is white; accept if we don't have a color yet.
      if myColor == nil {
        myColor = .black
        peers.send(.init(kind: .acceptRole))
      }
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
  boardSnapshots = [engine.board]
    if send { peers.send(.init(kind: .reset)) }
  saveGame()
  }

  func respondToResetRequest(accept: Bool) {
    if accept {
      peers.send(.init(kind: .acceptReset))
      performLocalReset(send: true)
    } else {
      peers.send(.init(kind: .declineReset))
      incomingResetRequest = false
    }
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
  }

  private func requestSync() {
    peers.send(.init(kind: .syncRequest))
  }

  private func sendSnapshot() {
    let msg = NetMessage(kind: .syncState,
                         move: nil,
                         color: nil,
                         deviceName: peers.localFriendlyName,
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
        if let cap = capturedBefore {
          if myColor == engine.sideToMove.opposite { // move just made by me
            capturedByMe.append(cap)
            lastCapturedPieceID = cap.id
            lastCaptureByMe = true
          } else if myColor != nil { // opponent capture path (unlikely here)
            capturedByOpponent.append(cap)
            lastCapturedPieceID = cap.id
            lastCaptureByMe = false
          }
        } else {
          lastCapturedPieceID = nil
          lastCaptureByMe = nil
        }
        movesMade += 1
        lastMove = base
        if peers.isConnected { peers.send(.init(kind: .move, move: base)) }
  moveHistory.append(base)
  historyIndex = nil
  boardSnapshots.append(engine.board)
  saveGame()
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
  }

  // Reconstruct a board state after n moves from history (n in 0...moveHistory.count)
  func boardAfterMoves(_ n: Int) -> Board {
  if n < boardSnapshots.count { return boardSnapshots[n] }
  if n == moveHistory.count { return engine.board }
  // Sollte nicht vorkommen: Snapshots unvollständig. Rekonstruiere flüchtig ohne zu publishen (vermeidet Warning in View).
  var e = ChessEngine()
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

    // Reconstruct captured pieces up to idx moves
    var engine = ChessEngine()
    var capsByWhite: [Piece] = []
    var capsByBlack: [Piece] = []

    for i in 0..<min(idx, moveHistory.count) {
      let move = moveHistory[i]
      // Detect capture before making move
      if let piece = engine.board.piece(at: move.to) { // normal capture
        if piece.color == .white { capsByBlack.append(piece) } else { capsByWhite.append(piece) }
      } else {
        // Possible en passant
        if let moving = engine.board.piece(at: move.from), moving.type == .pawn, move.from.file != move.to.file, engine.board.piece(at: move.to) == nil {
          // en passant target square is behind destination
          let dir = moving.color == .white ? 1 : -1
          let capturedSq = Square(file: move.to.file, rank: move.to.rank - dir)
          if let epPawn = engine.board.piece(at: capturedSq), epPawn.color != moving.color, epPawn.type == .pawn {
            if epPawn.color == .white { capsByBlack.append(epPawn) } else { capsByWhite.append(epPawn) }
          }
        }
      }
      _ = engine.tryMakeMove(move)
    }

    let myHistoricalPieces: [Piece]
    let opponentHistoricalPieces: [Piece]

    // Determine whose perspective 'forMe' refers to
    if let my = myColor { // connected mode
      myHistoricalPieces = my == .white ? capsByWhite : capsByBlack
      opponentHistoricalPieces = my == .white ? capsByBlack : capsByWhite
    } else { // single device: 'forMe' shows white's captures at bottom
      myHistoricalPieces = forMe ? capsByWhite : capsByBlack
      opponentHistoricalPieces = forMe ? capsByBlack : capsByWhite
    }

    let myPoints = myHistoricalPieces.reduce(0) { $0 + pieceValue($1) }
    let opponentPoints = opponentHistoricalPieces.reduce(0) { $0 + pieceValue($1) }

    return forMe ? (myPoints - opponentPoints) : (opponentPoints - myPoints)
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
    var engine = ChessEngine()
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
    // If we already have a full snapshot sequence (count == moveHistory.count + 1) and first snapshot matches current initial board piece set, skip.
    if boardSnapshots.count == moveHistory.count + 1 {
      return
    }
    var e = ChessEngine()
    var newSnapshots: [Board] = [e.board] // initial position
    for mv in moveHistory {
      _ = e.tryMakeMove(mv)
      newSnapshots.append(e.board)
    }
    // Replace engine only if our current engine position mismatches last reconstructed (safety for loaded V1/V2)
    if let last = newSnapshots.last, !boardsEqual(last, engine.board) {
      // Adopt reconstructed engine snapshot to align identities for future moves
      engine = ChessEngine.fromSnapshot(board: last, sideToMove: (moveHistory.count % 2 == 0) ? .white : .black)
    }
    boardSnapshots = newSnapshots
  }

  /// Lightweight board equality (piece type & color at each square)
  private func boardsEqual(_ a: Board, _ b: Board) -> Bool {
    for rank in 0..<8 { for file in 0..<8 { let sq = Square(file: file, rank: rank); let pa = a.piece(at: sq); let pb = b.piece(at: sq); if pa?.type != pb?.type || pa?.color != pb?.color { return false } } }
    return true
  }
}
