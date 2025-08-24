import XCTest
@testable import ChessDuo

final class ReconnectionPersistenceTests: XCTestCase {
  // Simulates one VM receiving local + remote moves (with distinct originIDs), then restart & sync.
  func testReconnectionPersistsTwoParticipantsAndAvoidsReset() throws {
    let vm = TestHelpers.freshCleanVM()
    XCTAssertEqual(vm.movesMade, 0, "Fresh VM should have no moves after clearing persistence")
    vm.myColor = .white
    let localID = vm.stableOriginID
    let remoteID = "REMOTE-TEST-ID"

    // White local move (use makeMove path to reflect multiplayer; ensure color + side align)
    guard let e2 = Square(algebraic: "e2"), let e4 = Square(algebraic: "e4") else { XCTFail("Squares"); return }
    XCTAssertTrue(vm.engine.sideToMove == .white)
    // makeMove requires myColor == sideToMove
    XCTAssertTrue(vm.makeMove(from: e2, to: e4))
    XCTAssertEqual(vm.movesMade, 1)
    XCTAssertNil(vm.sessionParticipantsSnapshot)

    // Inject remote black reply (e7e5) with distinct originID
    guard let e7 = Square(algebraic: "e7"), let e5 = Square(algebraic: "e5") else { XCTFail("Squares"); return }
    var remoteMove = NetMessage(kind: .move, move: Move(from: e7, to: e5))
    remoteMove.originID = remoteID
    vm.handle(remoteMove)

    // After remote move snapshot should auto-capture
    XCTAssertEqual(vm.movesMade, 2)
    XCTAssertEqual(vm.sessionParticipantsSnapshot?.count, 2)
    let snapBefore = vm.sessionParticipantsSnapshot!
    XCTAssertTrue(snapBefore.contains(localID) && snapBefore.contains(remoteID))

    // Persist & restart (do NOT use freshCleanVM for the reloaded instance; that would delete the just-saved file)
    vm.saveGame()
    let vm2 = GameViewModel()
    vm2.loadGameIfAvailable()
    XCTAssertEqual(vm2.movesMade, 2)
    XCTAssertEqual(vm2.sessionParticipantsSnapshot?.count, 2)
    let snapAfter = vm2.sessionParticipantsSnapshot!
    XCTAssertEqual(Set(snapBefore), Set(snapAfter))

    // Simulate remote sync with identical participants (should neither reset nor adopt since moves equal)
    var sync = NetMessage(kind: .syncState)
    sync.board = vm.engine.board
    sync.sideToMove = vm.engine.sideToMove
    sync.movesMade = vm.movesMade
    sync.capturedByMe = vm.capturedByMe
    sync.capturedByOpponent = vm.capturedByOpponent
    sync.sessionParticipants = snapBefore
    sync.moveHistory = vm.moveHistory
    vm2.handle(sync)
    XCTAssertEqual(vm2.movesMade, 2)
    XCTAssertEqual(vm2.sessionParticipantsSnapshot?.count, 2)
  }
}
