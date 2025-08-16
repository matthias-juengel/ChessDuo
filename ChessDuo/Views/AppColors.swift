import SwiftUI

// Central semantic color palette for ChessDuo.
// Adjust values here to theme the entire app.
struct AppColors {
  // Board squares
  static let boardDark = Color(red: 0.40, green: 0.40, blue: 0.40)
  static let boardLight = Color(red: 0.60, green: 0.60, blue: 0.60)

  // Coordinate labels (contrasts)
  static let coordLight = Color(red: 0.75, green: 0.75, blue: 0.75)
  static let coordDark  = Color(red: 0.25, green: 0.25, blue: 0.25)

  // Backgrounds / overlays
  static let turnBase = Color(red: 0.50, green: 0.50, blue: 0.50)
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
  static let moveIndicatorQuietOnLight = Color.black.opacity(0.3)  // subtle on light square
  static let moveIndicatorQuietOnDark  = Color.white.opacity(0.3)  // brighter on dark square
  static let moveIndicatorCaptureOnLight = Color.black.opacity(0.2) // Color(red: 0.55, green: 0.10, blue: 0.10).opacity(0.70)
  static let moveIndicatorCaptureOnDark  = Color.white.opacity(0.2) // Color(red: 1.00, green: 0.40, blue: 0.40).opacity(0.85)

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
