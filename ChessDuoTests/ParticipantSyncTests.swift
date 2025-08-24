import XCTest
@testable import ChessDuo

final class ParticipantSyncTests: XCTestCase {
  func testSingleSideMoveDoesNotCaptureParticipantsSnapshot() throws {
    // Case A: Local makes the very first move (white) -> snapshot must remain nil
    do {
      let vm = TestHelpers.freshCleanVM()
      vm.myColor = .white
      XCTAssertNil(vm.sessionParticipantsSnapshot, "Precondition: no snapshot at start")
      guard let e2 = Square(algebraic: "e2"), let e4 = Square(algebraic: "e4") else { XCTFail("Squares"); return }
      XCTAssertTrue(vm.makeMove(from: e2, to: e4))
      XCTAssertEqual(vm.movesMade, 1)
      XCTAssertNil(vm.sessionParticipantsSnapshot, "Single local move should NOT create participants snapshot")
      // Persist & reload to ensure we did not accidentally serialize a snapshot
      vm.saveGame()
      let reloaded = GameViewModel()
      XCTAssertEqual(reloaded.movesMade, 1, "Move count should persist")
      XCTAssertNil(reloaded.sessionParticipantsSnapshot, "Participants snapshot must still be nil after reload with only one participant")
    }

    // Case B: Remote makes the very first move (white) while we are black -> snapshot must remain nil
    do {
      let vm = TestHelpers.freshCleanVM()
      vm.myColor = .black // We are expecting the opponent (white) to move first
      XCTAssertNil(vm.sessionParticipantsSnapshot)
      guard let e2 = Square(algebraic: "e2"), let e4 = Square(algebraic: "e4") else { XCTFail("Squares"); return }
      var msg = NetMessage(kind: .move, move: Move(from: e2, to: e4))
      let remoteID = "RemoteFIRST#WHITE"
      msg.originID = remoteID
      vm.handle(msg)
      XCTAssertEqual(vm.movesMade, 1)
      XCTAssertNil(vm.sessionParticipantsSnapshot, "Single remote move should NOT create participants snapshot")
      vm.saveGame()
      let reloaded = GameViewModel()
      XCTAssertEqual(reloaded.movesMade, 1)
      XCTAssertNil(reloaded.sessionParticipantsSnapshot, "Participants snapshot must remain nil after reload when only one remote participant has moved")
    }
  }
  func testSnapshotCapturedOnlyAfterBothSidesMove() throws {
    let vm = TestHelpers.freshCleanVM()
    vm.myColor = .white
    // Before any move: no snapshot
    XCTAssertNil(vm.sessionParticipantsSnapshot)
    // Local (white) move e2e4
    guard let e2 = Square(algebraic: "e2"), let e4 = Square(algebraic: "e4") else { XCTFail("Squares"); return }
    XCTAssertTrue(vm.makeMove(from: e2, to: e4))
    XCTAssertEqual(vm.movesMade, 1)
    // Still only one participant has moved
    XCTAssertNil(vm.sessionParticipantsSnapshot, "Snapshot should not yet be captured after only one side's move")
    // Simulate remote black move e7e5 via NetMessage
    guard let e7 = Square(algebraic: "e7"), let e5 = Square(algebraic: "e5") else { XCTFail("Squares"); return }
    let remoteID = "RemoteDevice#ABC12345"
    var msg = NetMessage(kind: .move, move: Move(from: e7, to: e5))
    msg.originID = remoteID
    vm.handle(msg)
    XCTAssertEqual(vm.movesMade, 2)
    // Now both participants should be recorded and snapshot captured
    let snap = vm.sessionParticipantsSnapshot
    XCTAssertNotNil(snap, "Snapshot should be captured after both sides have moved")
  XCTAssertEqual(Set(snap!), Set([vm.stableOriginID, remoteID]))
  }

  func testRestartPreservesParticipantsAndAvoidsResetOnSync() throws {
    // Set up initial game with two moves (white & black)
    var vm: GameViewModel! = TestHelpers.freshCleanVM()
    vm.myColor = .white
    guard let e2 = Square(algebraic: "e2"), let e4 = Square(algebraic: "e4"),
          let e7 = Square(algebraic: "e7"), let e5 = Square(algebraic: "e5") else { XCTFail("Squares"); return }
    XCTAssertTrue(vm.makeMove(from: e2, to: e4))
    let remoteID = "RemoteDevice#ABC12345"
    var blackMsg = NetMessage(kind: .move, move: Move(from: e7, to: e5))
    blackMsg.originID = remoteID
    vm.handle(blackMsg)
    XCTAssertEqual(vm.movesMade, 2)
    XCTAssertNotNil(vm.sessionParticipantsSnapshot)
  let persistedParticipants = vm.sessionParticipantsSnapshot!
    // Force save
    vm.saveGame()
    // Capture board snapshot for later sync message
    let board = vm.engine.board
    let sideToMove = vm.engine.sideToMove
    vm = nil
    // Simulate app restart (new instance loads persistence)
    let restarted = GameViewModel()
    // After load, movesMade may be 2 (or baselineTrusted); ensure participants snapshot restored
    XCTAssertEqual(restarted.sessionParticipantsSnapshot, persistedParticipants, "Participants snapshot should persist across restart")
    let preMoves = restarted.movesMade
    XCTAssertEqual(preMoves, 2, "Moves should persist across restart (expected 2)")
    // Simulate remote sending a syncState with SAME participants and equal move count
    var sync = NetMessage(kind: .syncState)
    sync.originID = remoteID
    sync.board = board
    sync.sideToMove = sideToMove
    sync.movesMade = 2
    sync.capturedByMe = []
    sync.capturedByOpponent = []
  sync.sessionParticipants = persistedParticipants
    restarted.handle(sync)
    // Ensure we did not reset (moves should remain 2 and snapshot intact)
    XCTAssertEqual(restarted.movesMade, 2)
    XCTAssertEqual(restarted.sessionParticipantsSnapshot, persistedParticipants)
  }
}
