import Testing
import XCTest
@testable import ChessDuo

// Bridge to allow -only-testing selection under xcodebuild which sometimes
// fails to enumerate pure swift-testing tests by name. We expose an XCTestCase
// subclass that calls into the async swift-testing test logic.
final class CaptureHighlightTests_XCTest: XCTestCase {
  func testLiveCaptureHighlightAppears() throws {
    let exp = expectation(description: "swift-testing live capture")
    Task {
      do {
        try await CaptureHighlightTests.runCaptureScenario()
        exp.fulfill()
      } catch {
        XCTFail("swift-testing failure: \(error)")
      }
    }
    wait(for: [exp], timeout: 2.0)
  }
}

struct CaptureHighlightTests {
  // Swift-Testing version disabled (handled by XCTest wrapper above) to avoid duplicate execution under xcodebuild.
  // If re-enabling, ensure no race with animation wrappers.
  static func runCaptureScenario() async throws {
    let fen = "r3k3/8/8/8/8/8/8/R3K3 w - - 0 1"
    let vm = TestHelpers.freshCleanVM()
    let game = FamousGame(title: "Capture Test", players: "", description: "", moves: [], pgn: nil, initialFEN: fen, localizations: nil, category: .endgame)
    vm.applyFamousGame(game, broadcast: false)
    let from = Square(file: 0, rank: 0)
    let to = Square(file: 0, rank: 7)
    XCTAssertTrue(vm.makeLocalMove(from: from, to: to), "Rook move a1->a8 should be legal")
    XCTAssertNotNil(vm.lastCapturedPieceID)
    XCTAssertEqual(vm.lastCaptureByMe, true)
    let capturedIDs = Set(vm.capturedByMe.map { $0.id })
    if capturedIDs.contains(vm.lastCapturedPieceID!) {
      // OK
    } else {
      let oppIDs = Set(vm.capturedByOpponent.map { $0.id })
      XCTAssertTrue(oppIDs.contains(vm.lastCapturedPieceID!), "Captured piece id should appear in either perspective list")
    }
  }
}
