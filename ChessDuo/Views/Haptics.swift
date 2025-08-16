import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Centralized lightweight haptics wrapper so calls are concise & easily adjustable.
// Use optional semantics; on unsupported platforms these are no-ops.
struct Haptics {
  static func lightImpact() {
  #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  #endif
  }
  static func mediumImpact() {
  #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  #endif
  }
  static func heavyImpact() {
  #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
  #endif
  }
  static func success() {
  #if canImport(UIKit)
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  #endif
  }
  static func warning() {
  #if canImport(UIKit)
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
  #endif
  }
  static func error() {
  #if canImport(UIKit)
    UINotificationFeedbackGenerator().notificationOccurred(.error)
  #endif
  }
}
