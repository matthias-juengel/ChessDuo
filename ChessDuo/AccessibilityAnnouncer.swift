import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Central helper to post accessibility announcements (VoiceOver, etc.).
/// Use `AccessibilityAnnouncer.postTurnChange(for:myColor:connected:)` when side to move changes.
enum AccessibilityAnnouncer {
  static func announce(_ message: String) {
    #if canImport(UIKit)
    UIAccessibility.post(notification: .announcement, argument: message)
    #endif
  }

  /// Announce a turn change. In single-device mode we always announce the side to move as "Your turn" (since both players share device).
  /// In connected mode we differentiate between local player and opponent.
  static func postTurnChange(for sideToMove: PieceColor, myColor: PieceColor?, connected: Bool) {
    let key: String
    if connected {
      if let mine = myColor, mine == sideToMove {
        key = (sideToMove == .white) ? "announce_your_turn_white" : "announce_your_turn_black"
      } else {
        key = (sideToMove == .white) ? "announce_opponent_turn_white" : "announce_opponent_turn_black"
      }
    } else {
      key = (sideToMove == .white) ? "announce_your_turn_white" : "announce_your_turn_black"
    }
    announce(String.loc(key))
  }
}
