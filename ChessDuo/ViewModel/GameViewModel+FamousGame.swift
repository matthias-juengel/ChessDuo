//
//  GameViewModel+FamousGame.swift
//  Extracted from GameViewModel.swift (no behavior changes)
//

import Foundation

extension GameViewModel {
  func userSelectedFamousGame(_ game: FamousGame) {
    if peers.isConnected, sessionProgressed {
      pendingGameToLoad = game
      awaitingLoadGameConfirmation = true
      peers.send(.init(kind: .requestLoadGame, gameTitle: game.title))
    } else if peers.isConnected {
      applyFamousGame(game, broadcast: true)
    } else {
      applyFamousGame(game, broadcast: false)
    }
  }

  func respondToLoadGameRequest(accept: Bool) {
    guard let title = incomingLoadGameRequestTitle else { return }
    if accept {
      peers.send(.init(kind: .acceptLoadGame, gameTitle: title))
    } else {
      peers.send(.init(kind: .declineLoadGame, gameTitle: title))
    }
    incomingLoadGameRequestTitle = nil
  }

  func applyFamousGame(_ game: FamousGame, broadcast: Bool) {
    if let fen = game.initialFEN, let custom = ChessEngine.fromFEN(fen) { engine = custom } else { engine = ChessEngine() }
    baselineBoard = engine.board
    baselineSideToMove = engine.sideToMove
    baselineCounts = pieceCounts(on: baselineBoard)
    baselineTrusted = true
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
      var parsingEngine = engine // start from current (possibly custom FEN) position
      switch PGNParser.parseMoves(pgn: pgn, startingFrom: &parsingEngine) {
      case .success(let parsed):
        // Keep engine at the starting position; apply parsed moves below to build history/snapshots
        sourceMoves = parsed
      case .failure(let err):
        print("PGN parse failed for game \(game.title): \(err)")
      }
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
                           gameTitle: game.title,
                           initialFEN: game.initialFEN)
      peers.send(msg)
    }
  }
}
