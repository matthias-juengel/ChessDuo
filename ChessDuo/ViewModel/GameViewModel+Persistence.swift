//
//  GameViewModel+Persistence.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation

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
  struct GamePersistedV3: Codable { // adds baseline board & side
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
    let baselineBoard: Board
    let baselineSideToMove: PieceColor
  }
  struct GamePersistedV4: Codable { // adds stable captured archives
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
    let baselineBoard: Board
    let baselineSideToMove: PieceColor
    let whiteCapturedPieces: [Piece]
    let blackCapturedPieces: [Piece]
  }
  struct GamePersistedV5: Codable { // adds participants snapshot
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
    let baselineBoard: Board
    let baselineSideToMove: PieceColor
    let whiteCapturedPieces: [Piece]
    let blackCapturedPieces: [Piece]
    let sessionParticipants: [String]?
  }

  var saveURL: URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    // If running inside a test bundle, segregate persistence to avoid colliding with on-device prod data.
    #if DEBUG
    let isTesting: Bool = (NSClassFromString("XCTestCase") != nil)
    #else
    let isTesting: Bool = false
    #endif
    let folderName = isTesting ? "ChessDuo-Test" : "ChessDuo"
    let dir = base.appendingPathComponent(folderName, isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir.appendingPathComponent("game.json")
  }

  func saveGame() {
  let snapshot = GamePersistedV5(version: 5,
                   engine: engine,
                   myColor: myColor,
                   capturedByMe: capturedByMe,
                   capturedByOpponent: capturedByOpponent,
                   movesMade: movesMade,
                   lastMove: lastMove,
                   lastCapturedPieceID: lastCapturedPieceID,
                   lastCaptureByMe: lastCaptureByMe,
                   moveHistory: moveHistory,
                   baselineBoard: baselineBoard,
                   baselineSideToMove: baselineSideToMove,
                   whiteCapturedPieces: whiteCapturedPieces,
                   blackCapturedPieces: blackCapturedPieces,
                   sessionParticipants: sessionParticipantsSnapshot)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    do {
      let data = try encoder.encode(snapshot)
      let tmp = saveURL.appendingPathExtension("tmp")
  try data.write(to: tmp, options: .atomic)
      try? FileManager.default.removeItem(at: saveURL)
      try FileManager.default.moveItem(at: tmp, to: saveURL)
    } catch {
      print("Save failed", error)
    }
  }

  func loadGameIfAvailable() {
    let url = saveURL
    guard let data = try? Data(contentsOf: url) else { return }
    let decoder = JSONDecoder()
    if let v5 = try? decoder.decode(GamePersistedV5.self, from: data) {
      print("[PERSIST] Loading V5 game: moves=\(v5.movesMade) myColor=\(String(describing: v5.myColor)) lastMove=\(String(describing: v5.lastMove)) participants=\(String(describing: v5.sessionParticipants))")
      engine = v5.engine
      myColor = v5.myColor
      capturedByMe = v5.capturedByMe
      capturedByOpponent = v5.capturedByOpponent
      movesMade = v5.movesMade
      lastMove = v5.lastMove
      lastCapturedPieceID = v5.lastCapturedPieceID
      lastCaptureByMe = v5.lastCaptureByMe
      moveHistory = v5.moveHistory
      baselineBoard = v5.baselineBoard
      baselineSideToMove = v5.baselineSideToMove
      baselineCounts = pieceCounts(on: baselineBoard)
      baselineTrusted = true
      boardSnapshots = []
      whiteCapturedPieces = v5.whiteCapturedPieces
      blackCapturedPieces = v5.blackCapturedPieces
      sessionParticipantsSnapshot = v5.sessionParticipants
      if let snap = sessionParticipantsSnapshot, snap.count >= 2 {
        actualParticipants = Set(snap)
      }
    } else if let v4 = try? decoder.decode(GamePersistedV4.self, from: data) {
      print("[PERSIST] Loading V4 game: moves=\(v4.movesMade) myColor=\(String(describing: v4.myColor)) lastMove=\(String(describing: v4.lastMove))")
      engine = v4.engine
      myColor = v4.myColor
      capturedByMe = v4.capturedByMe
      capturedByOpponent = v4.capturedByOpponent
      movesMade = v4.movesMade
      lastMove = v4.lastMove
      lastCapturedPieceID = v4.lastCapturedPieceID
      lastCaptureByMe = v4.lastCaptureByMe
      moveHistory = v4.moveHistory
      baselineBoard = v4.baselineBoard
      baselineSideToMove = v4.baselineSideToMove
      baselineCounts = pieceCounts(on: baselineBoard)
      baselineTrusted = true
      boardSnapshots = []
  if let snap = sessionParticipantsSnapshot, snap.count >= 2 { actualParticipants = Set(snap) }
      whiteCapturedPieces = v4.whiteCapturedPieces
      blackCapturedPieces = v4.blackCapturedPieces
    } else if let v3 = try? decoder.decode(GamePersistedV3.self, from: data) {
      print("[PERSIST] Loading V3 game: moves=\(v3.movesMade) myColor=\(String(describing: v3.myColor)) lastMove=\(String(describing: v3.lastMove))")
      engine = v3.engine
      myColor = v3.myColor
      capturedByMe = v3.capturedByMe
      capturedByOpponent = v3.capturedByOpponent
      movesMade = v3.movesMade
      lastMove = v3.lastMove
      lastCapturedPieceID = v3.lastCapturedPieceID
      lastCaptureByMe = v3.lastCaptureByMe
      moveHistory = v3.moveHistory
      baselineBoard = v3.baselineBoard
      baselineSideToMove = v3.baselineSideToMove
      baselineCounts = pieceCounts(on: baselineBoard)
      baselineTrusted = true
      boardSnapshots = []
      if let snap = sessionParticipantsSnapshot, snap.count >= 2 { actualParticipants = Set(snap) }
    } else if let v2 = try? decoder.decode(GamePersistedV2.self, from: data) {
      print("[PERSIST] Loading V2 game: moves=\(v2.movesMade) myColor=\(String(describing: v2.myColor)) lastMove=\(String(describing: v2.lastMove))")
      engine = v2.engine
      myColor = v2.myColor
      capturedByMe = v2.capturedByMe
      capturedByOpponent = v2.capturedByOpponent
      movesMade = v2.movesMade
      lastMove = v2.lastMove
      lastCapturedPieceID = v2.lastCapturedPieceID
      lastCaptureByMe = v2.lastCaptureByMe
      moveHistory = v2.moveHistory
      boardSnapshots = []
      baselineBoard = engine.board
      baselineSideToMove = engine.sideToMove
      baselineCounts = pieceCounts(on: baselineBoard)
      baselineTrusted = false
      if let snap = sessionParticipantsSnapshot, snap.count >= 2 { actualParticipants = Set(snap) }
    } else if let v1 = try? decoder.decode(GamePersistedV1.self, from: data) {
      print("[PERSIST] Loading V1 game: moves=\(v1.movesMade) myColor=\(String(describing: v1.myColor)) lastMove=\(String(describing: v1.lastMove))")
      engine = v1.engine
      myColor = v1.myColor
      capturedByMe = v1.capturedByMe
      capturedByOpponent = v1.capturedByOpponent
      movesMade = v1.movesMade
      lastMove = v1.lastMove
      lastCapturedPieceID = v1.lastCapturedPieceID
      lastCaptureByMe = v1.lastCaptureByMe
      moveHistory = []
      boardSnapshots = []
      baselineBoard = engine.board
      baselineSideToMove = engine.sideToMove
      baselineCounts = pieceCounts(on: baselineBoard)
      baselineTrusted = false
      if let snap = sessionParticipantsSnapshot, snap.count >= 2 { actualParticipants = Set(snap) }
    }
    rebuildSnapshotsFromHistory()
    if let mine = myColor { preferredPerspective = mine }
    sessionProgressed = movesMade > 0
    print("[PERSIST] Loaded game summary participantsSnap=\(String(describing: sessionParticipantsSnapshot)) moves=\(movesMade) opp=\(opponentName ?? "<none>")")
  }
}
