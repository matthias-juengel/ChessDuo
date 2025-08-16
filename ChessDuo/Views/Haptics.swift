import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Central haptics configuration.
// Adjust the mapping in `patternForEvent` to globally change feedback.
enum HapticEvent: CaseIterable {
  case pieceSelected
  case pieceReSelected
  case moveSuccess
  case moveNowMyTurn
  case promotionAppear
  case promotionSelect
  case promotionCancel
  case resetRequestIncoming
  case resetAccept
  case resetDecline
  case newGameConfirm
  case newGameKeepPlaying
}

enum HapticPattern {
  case none
  case impactLight
  case impactMedium
  case impactHeavy
  case impactLightDouble // two very soft light taps in quick succession
  case notifySuccess
  case notifyWarning
  case notifyError
}

struct Haptics {
  // Map events to patterns (single place to customize)
  static func patternForEvent(_ event: HapticEvent) -> HapticPattern {
    switch event {
    case .pieceSelected: return .impactLight
    case .pieceReSelected: return .impactLight
    case .moveSuccess: return .impactMedium
  case .moveNowMyTurn: return .impactLightDouble
    case .promotionAppear: return .none
    case .promotionSelect: return .notifySuccess
    case .promotionCancel: return .impactLight
    case .resetRequestIncoming: return .notifyWarning
    case .resetAccept: return .notifySuccess
    case .resetDecline: return .impactLight
    case .newGameConfirm: return .notifySuccess
    case .newGameKeepPlaying: return .impactLight
    }
  }

  static func trigger(_ event: HapticEvent) {
    fire(patternForEvent(event))
  }

  // Direct pattern fire (internal)
  private static func fire(_ pattern: HapticPattern) {
  #if canImport(UIKit)
    switch pattern {
    case .none: return
    case .impactLight: UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .impactMedium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .impactHeavy: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case .impactLightDouble:
      let gen = UIImpactFeedbackGenerator(style: .light)
      gen.prepare()
      // First, a soft tap
      if #available(iOS 13.0, *) {
        gen.impactOccurred(intensity: 0.45)
      } else {
        gen.impactOccurred()
      }
      // Second, an even softer follow-up after a short delay (~70–80ms feels subtle)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        if #available(iOS 13.0, *) {
          gen.impactOccurred(intensity: 0.45)
        } else {
          gen.impactOccurred()
        }
      }
    case .notifySuccess: UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .notifyWarning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .notifyError: UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
  #endif
  }

  // Legacy direct calls (kept if some views still use them; can be removed after full migration)
  static func lightImpact() { fire(.impactLight) }
  static func mediumImpact() { fire(.impactMedium) }
  static func heavyImpact() { fire(.impactHeavy) }
  static func success() { fire(.notifySuccess) }
  static func warning() { fire(.notifyWarning) }
  static func error() { fire(.notifyError) }
}
