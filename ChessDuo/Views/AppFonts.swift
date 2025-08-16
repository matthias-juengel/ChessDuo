import SwiftUI

// Central semantic typography palette for ChessDuo.
// Goal: one place to adjust font hierarchy (sizes/weights) while
// still allowing Dynamic Type scaling.
// Use in views: .font(AppFonts.title) etc. For variable sizes
// that depend on geometry (e.g. piece symbols) keep inline logic.
struct AppFonts {
  // MARK: - Core hierarchy
  // Large page / modal titles
  static let title = Font.title2.weight(.bold)
  // Section headers or secondary titles
  static let subtitle = Font.title3.weight(.semibold)
  // Primary body text
  static let body = Font.body
  // Supporting / explanatory text
  static let callout = Font.callout
  // Small auxiliary labels (coordinates etc.)
  static let caption = Font.caption

  // Monospaced (if needed later for debugging / engine output)
  static let monoBody = Font.system(.body, design: .monospaced)

  // MARK: - Helpers
  // Apply a custom font style with optional bold & smallCaps toggles.
  static func custom(_ base: Font, bold: Bool = false, smallCaps: Bool = false) -> Font {
    var f = base
    if bold { f = f.weight(.bold) }
    // smallCaps in SwiftUI currently via FontFeatures not widely exposed; omitted for simplicity.
    return f
  }
}

// Convenience view modifiers to reduce repetition when mixing weight & style.
extension View {
  func appFont(_ font: Font) -> some View { self.font(font) }
  func appTitle() -> some View { self.font(AppFonts.title) }
  func appSubtitle() -> some View { self.font(AppFonts.subtitle) }
  func appBody() -> some View { self.font(AppFonts.body) }
  func appCallout() -> some View { self.font(AppFonts.callout) }
  func appCaption() -> some View { self.font(AppFonts.caption) }
}
