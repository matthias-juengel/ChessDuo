import XCTest
@testable import ChessDuo

/// Tests for adopting an existing remote multiplayer game when local is fresh or only has solo progress.
final class SyncAdoptionTests: XCTestCase {
    // Helper to fabricate a remote snapshot message
    private func multiplayerSnapshot(from vm: GameViewModel) -> NetMessage {
        var msg = NetMessage(kind: .syncState)
        msg.board = vm.engine.board
        msg.sideToMove = vm.engine.sideToMove
        msg.movesMade = vm.movesMade
        msg.capturedByMe = vm.capturedByMe
        msg.capturedByOpponent = vm.capturedByOpponent
        msg.lastMoveFrom = vm.lastMove?.from
        msg.lastMoveTo = vm.lastMove?.to
        msg.lastCapturedPieceID = vm.lastCapturedPieceID
        msg.lastCaptureByMe = vm.lastCaptureByMe
        msg.moveHistory = vm.moveHistory
        msg.sessionParticipants = vm.sessionParticipantsSnapshot ?? Array(vm.actualParticipants).sorted()
        msg.originID = vm.stableOriginID
        return msg
    }

    /// Build a progressed multiplayer VM by playing two moves (white then black) so two participants exist.
    private func buildRemoteMultiplayerVM() -> GameViewModel {
        let white = TestHelpers.freshCleanVM()
        let black = TestHelpers.freshCleanVM()
        white._testResetStableIdentity(to: UUID().uuidString)
        black._testResetStableIdentity(to: UUID().uuidString)
        // Assign colors deterministically
        white.myColor = .white
        black.myColor = .black
        // White move: e2e4
        guard let e2 = Square(algebraic: "e2"), let e4 = Square(algebraic: "e4") else { return white }
        let m1 = Move(from: e2, to: e4)
        _ = white.engine.tryMakeMove(m1)
        white.moveHistory.append(m1)
        white.boardSnapshots.append(white.engine.board)
        white.movesMade = 1
        white.actualParticipants.insert(white.stableOriginID)
        // Sync black perspective via message
        var mvMsg = NetMessage(kind: .move, move: m1, color: nil, deviceName: nil)
        mvMsg.originID = white.stableOriginID
        black.handle(mvMsg)
        // Black reply move: e7e5
        guard let e7 = Square(algebraic: "e7"), let e5 = Square(algebraic: "e5") else { return white }
        let m2 = Move(from: e7, to: e5)
        _ = black.engine.tryMakeMove(m2)
        black.moveHistory.append(m2)
        black.boardSnapshots.append(black.engine.board)
        black.movesMade = 2
        black.actualParticipants.insert(black.stableOriginID)
        // Feed black's move back to white
        var mvMsg2 = NetMessage(kind: .move, move: m2, color: nil, deviceName: nil)
        mvMsg2.originID = black.stableOriginID
        white.handle(mvMsg2)
        // Ensure both have participants snapshot
        white.ensureParticipantsSnapshotIfNeeded(trigger: "testSetup")
        black.ensureParticipantsSnapshotIfNeeded(trigger: "testSetup")
        // Return one perspective (white) which now has full history (movesMade should be 2 there too)
        return white
    }

    func testFreshReturningParticipantAdoptsRemoteMultiplayerGame() {
        let remote = buildRemoteMultiplayerVM()
        let fresh = TestHelpers.freshCleanVM()
        fresh._testResetStableIdentity(to: UUID().uuidString)
        XCTAssertEqual(fresh.movesMade, 0)
        XCTAssertTrue(fresh.actualParticipants.isEmpty)
        // Simulate that fresh is actually a returning participant by inserting its ID into the remote participants list
        // (emulating that remote had previously captured a snapshot including this device).
        var snapshot = multiplayerSnapshot(from: remote)
        var participants = snapshot.sessionParticipants ?? []
        participants.append(fresh.stableOriginID)
        snapshot.sessionParticipants = Array(Set(participants)).sorted()
        fresh.handle(snapshot)
        XCTAssertEqual(fresh.movesMade, remote.movesMade, "Returning participant should adopt remote multiplayer game")
        XCTAssertEqual(fresh.moveHistory.count, remote.moveHistory.count)
        XCTAssertTrue(fresh.sessionParticipantsSnapshot?.count ?? 0 >= 2)
    }

    func testSoloReturningParticipantAdoptsRemoteMultiplayerGameOverwritesSoloProgress() {
        let remote = buildRemoteMultiplayerVM()
        let solo = TestHelpers.freshCleanVM()
        solo._testResetStableIdentity(to: UUID().uuidString)
        solo.myColor = .white
        // Solo makes a local move
        guard let e2 = Square(algebraic: "e2"), let e4 = Square(algebraic: "e4") else { XCTFail(); return }
        let m = Move(from: e2, to: e4)
        _ = solo.engine.tryMakeMove(m)
        solo.moveHistory.append(m)
        solo.boardSnapshots.append(solo.engine.board)
        solo.movesMade = 1
        solo.actualParticipants.insert(solo.stableOriginID)
        XCTAssertEqual(solo.movesMade, 1)
        // Remote snapshot augmented to include solo's ID (returning)
        var snapshot = multiplayerSnapshot(from: remote)
        var participants = snapshot.sessionParticipants ?? []
        participants.append(solo.stableOriginID)
        snapshot.sessionParticipants = Array(Set(participants)).sorted()
        solo.handle(snapshot)
        XCTAssertEqual(solo.movesMade, remote.movesMade, "Returning solo participant should adopt remote multiplayer game")
        XCTAssertEqual(solo.moveHistory.count, remote.moveHistory.count)
        XCTAssertTrue(solo.sessionParticipantsSnapshot?.contains(solo.stableOriginID) == true)
    }

    func testStrangerDoesNotAdoptRemoteMultiplayerGame() {
        let remote = buildRemoteMultiplayerVM()
        let stranger = TestHelpers.freshCleanVM()
        stranger._testResetStableIdentity(to: UUID().uuidString)
        let snapshot = multiplayerSnapshot(from: remote) // does NOT include stranger ID
        stranger.handle(snapshot)
        XCTAssertEqual(stranger.movesMade, 0, "Stranger should not adopt remote multiplayer game")
        XCTAssertTrue(stranger.moveHistory.isEmpty)
    }
}
