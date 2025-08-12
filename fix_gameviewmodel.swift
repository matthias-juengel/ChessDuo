// Temporary file to fix GameViewModel switch statement
// This content should replace the handle method in GameViewModel.swift

private func handle(_ msg: NetMessage) {
    switch msg.kind {
    case .hello:
        // nichts weiter nötig; Anzeige aktualisieren
        statusText = peers.isConnected ? "Verbunden" : statusText
    case .reset:
        engine.reset()
        statusText = "Neu gestartet. Am Zug: Weiß"
    case .move:
        if let m = msg.move {
            let capturedBefore = engine.board.piece(at: m.to)
            if engine.tryMakeMove(m) {
                if let cap = capturedBefore, cap.color == myColor { capturedByOpponent.append(cap) }
            }
            updateStatusAfterMove()
        }
    case .statusUpdate, .joinRequest, .joinResponse, .pairingCode, .gameSetup, .gameStart, .rematchRequest, .rematchResponse:
        // These message types are handled by the peer service layer
        break
    }
}