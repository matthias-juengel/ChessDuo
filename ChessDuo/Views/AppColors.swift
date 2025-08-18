import SwiftUI

// Central semantic color palette
// Adjust values here to theme the entire app.
struct AppColors {
  // Compact grayscale generator. v: 0.0 (black) ... 1.0 (white)
  // Optional alpha for convenience; default 1.0.

  // Hex helper: 0xRRGGBB and optional alpha (0.0–1.0)
  @inline(__always) private static func hex(_ rgb: UInt32, alpha: Double = 1.0) -> Color {
    let r = Double((rgb >> 16) & 0xFF) / 255.0
    let g = Double((rgb >> 8) & 0xFF) / 255.0
    let b = Double(rgb & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b).opacity(alpha)
  }

  static let highlight = hex(0x50847c)
  static let highlightLight = hex(0x80d2c6)


  @inline(__always) private static func gray(_ v: Double, _ a: Double = 1.0) -> Color {
    Color(red: v, green: v, blue: v).opacity(a)
  }
  // Board squares
  static let boardDark = gray(0.40)
  static let boardLight = gray(0.60)

  // Board border
  static let boardBorder = gray(0)

  // Coordinate labels (contrasts)
  static let coordLight = gray(0.75)
  static let coordDark  = gray(0.25)

  // Backgrounds / overlays
  static let turnBase = gray(0.50)
  static let turnHighlight = highlight
  static let backdrop = Color.black.opacity(0.55)
  static let captureHighlight = highlightLight.opacity(0.5)

  // Piece colors
  static let pieceWhite = Color.white
  static let pieceBlack = Color.black

  // Status / feedback
  static let highlightMove = highlight.opacity(0.45)
  static let check = AppColors.highlight
  static let checkmate = AppColors.highlightLight
  static let captureGlow = Color.white.opacity(0.60)

  static let dragCrosshair = gray(0.5, 1)

  // Move indicators (quiet target / capture target)
  // New per-square variants (light square vs dark square) for improved contrast
  static let moveIndicatorQuietOnLight = gray(0.0, 0.20)   // subtle on light square
  static let moveIndicatorQuietOnDark  = gray(1.0, 0.20)   // brighter on dark square
  static let moveIndicatorCaptureOnLight = gray(0.0, 0.15)
  static let moveIndicatorCaptureOnDark  = gray(1.0, 0.15)

  // Modal button backgrounds
  static let buttonPrimaryBG = Color.white.opacity(0.92)
  static let buttonSecondaryBG = Color.white.opacity(0.18)
  static let buttonDestructiveBG = highlight.opacity(0.85)
  static let buttonListBG = Color.white.opacity(0.12)
  static let buttonListStroke = Color.white.opacity(0.25)
  static let buttonSymbolBG = Color.white.opacity(0.18)
  static let buttonSymbolStroke = Color.white.opacity(0.35)

  // Text common
  static let textPrimary = Color.white
  static let textSecondary = Color.white.opacity(0.85)
  static let textTertiary = Color.white.opacity(0.80)
  static let textDark = Color.black

  // Misc
  static let shadowCard = Color.black.opacity(0.28)
}
