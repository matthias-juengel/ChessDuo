import SwiftUI

// Central Typography Map (compact & explicit)
// Shows what each semantic font maps to. Approximate default point sizes (iOS 17) in comments.
// We lean on built‑in Dynamic Type styles so scaling works automatically.
//
// Role                Style        Weight      ~Pt  Purpose
// ---------------------------------------------------------------
// title               title2       bold        22   Large modal / overlay titles
// subtitle            title3       semibold    20   Section headers / secondary titles
// body                body         regular     17   Primary text & paragraphs
// callout             callout      regular     16   Explanatory / helper text
// buttonLabel         callout      semibold    16   Emphasized inline buttons
// badge               caption      semibold    12   Small numeric highlights
// caption             caption      regular     12   Generic small labels
// boardCoordinate     caption2     semibold    11   File / rank markers on board
// monoBody            body(monosp) regular     17   Debug / engine output
//
// Add new roles here with a concise one‑line purpose.
struct AppFonts {
  // MARK: - Core hierarchy
  static let title           = Font.title2.weight(.bold)        // 22pt
  static let subtitle        = Font.title3.weight(.semibold)    // 20pt
  static let body            = Font.body                        // 17pt
  static let callout         = Font.callout                     // 16pt
  static let buttonLabel     = Font.callout.weight(.semibold)   // 16pt (emphasized)
  static let badge           = Font.caption.weight(.semibold)   // 12pt
  static let caption         = Font.caption                     // 12pt
  static let boardCoordinate = Font.caption.weight(.semibold)  // 11pt

  static let monoBody        = Font.system(.body, design: .monospaced) // 17pt monospaced

  // MARK: - Helpers
  // Apply a custom font style with optional bold & smallCaps toggles.
  static func custom(_ base: Font, bold: Bool = false, smallCaps: Bool = false) -> Font {
    var f = base
    if bold { f = f.weight(.bold) }
    // smallCaps in SwiftUI currently via FontFeatures not widely exposed; omitted for simplicity.
    return f
  }
}

// Convenience modifiers
extension View {
  func appFont(_ font: Font) -> some View { self.font(font) }
  func appTitle() -> some View { self.font(AppFonts.title) }
  func appSubtitle() -> some View { self.font(AppFonts.subtitle) }
  func appBody() -> some View { self.font(AppFonts.body) }
  func appCallout() -> some View { self.font(AppFonts.callout) }
  func appCaption() -> some View { self.font(AppFonts.caption) }
  func appButtonLabel() -> some View { self.font(AppFonts.buttonLabel) }
  func appBadge() -> some View { self.font(AppFonts.badge) }
  func appBoardCoordinate() -> some View { self.font(AppFonts.boardCoordinate) }
}

// MARK: - Optional Enum Mapping
// A lightweight registry for dynamic lookups or previews.
enum AppFontRole: CaseIterable, Identifiable { // Used only for preview & inspection
  case title, subtitle, body, callout, buttonLabel, badge, caption, boardCoordinate, monoBody
  var id: String { String(describing: self) }
  var font: Font {
    switch self {
    case .title: return AppFonts.title
    case .subtitle: return AppFonts.subtitle
    case .body: return AppFonts.body
    case .callout: return AppFonts.callout
    case .buttonLabel: return AppFonts.buttonLabel
    case .badge: return AppFonts.badge
    case .caption: return AppFonts.caption
    case .boardCoordinate: return AppFonts.boardCoordinate
    case .monoBody: return AppFonts.monoBody
    }
  }
}

// MARK: - Preview Support (Optional)
#if DEBUG
struct AppFonts_Preview: View {
  var body: some View {
    List {
      Section("Typography Roles") {
        ForEach(AppFontRole.allCases) { role in
          VStack(alignment: .leading, spacing: 2) {
            Text(String(describing: role)).font(.caption.monospaced())
            Text("The quick brown fox jumps over 12 lazy dogs.")
              .font(role.font)
          }
          .padding(.vertical, 4)
        }
      }
    }
    .navigationTitle("Fonts")
  }
}

struct AppFonts_Preview_Previews: PreviewProvider {
  static var previews: some View { NavigationView { AppFonts_Preview() } }
}
#endif
