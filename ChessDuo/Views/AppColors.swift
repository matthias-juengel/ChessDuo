import SwiftUI

// Central semantic color palette for ChessDuo.
// Adjust values here to theme the entire app.
struct AppColors {
  // Compact grayscale generator. v: 0.0 (black) ... 1.0 (white)
  // Optional alpha for convenience; default 1.0.
  @inline(__always) private static func gray(_ v: Double, _ a: Double = 1.0) -> Color {
    Color(red: v, green: v, blue: v).opacity(a)
  }
  // Board squares
  static let boardDark = gray(0.40)
  static let boardLight = gray(0.60)

  // Coordinate labels (contrasts)
  static let coordLight = gray(0.75)
  static let coordDark  = gray(0.25)

  // Backgrounds / overlays
  static let turnBase = gray(0.50)
  static let turnHighlight = Color.green.opacity(0.40)
  static let turnHighlightHalf = Color.green.opacity(0.38)
  static let backdrop = Color.black.opacity(0.55)

  // Piece colors
  static let pieceWhite = Color.white
  static let pieceBlack = Color.black

  // Status / feedback
  static let highlightMove = Color.green.opacity(0.45)
  static let check = Color.orange.opacity(0.70)
  static let checkmate = Color.red.opacity(0.90)
  static let captureGlow = Color.white.opacity(0.60)

  // Move indicators (quiet target / capture target)
  // New per-square variants (light square vs dark square) for improved contrast
  static let moveIndicatorQuietOnLight = gray(0.0, 0.20)   // subtle on light square
  static let moveIndicatorQuietOnDark  = gray(1.0, 0.20)   // brighter on dark square
  static let moveIndicatorCaptureOnLight = gray(0.0, 0.15)
  static let moveIndicatorCaptureOnDark  = gray(1.0, 0.15)

  // Modal button backgrounds
  static let buttonPrimaryBG = Color.white.opacity(0.92)
  static let buttonSecondaryBG = Color.white.opacity(0.18)
  static let buttonDestructiveBG = Color.red.opacity(0.85)
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
