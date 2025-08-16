import SwiftUI

struct CapturedRow: View {
  let pieces: [Piece]
  var rotatePieces: Bool = false
  var highlightPieceID: UUID? = nil
  var pointAdvantage: Int = 0 // material lead (positive only shown)
  private let maxBaseSize: CGFloat = 32
  private let minSize: CGFloat = 14
  var body: some View {
    GeometryReader { geo in
      let sorted = sortedPieces()
      let spacing: CGFloat = 4
      let count = CGFloat(sorted.count)
      let available = max(geo.size.width - (count - 1) * spacing, 10)
      let idealSize = min(maxBaseSize, available / max(count, 1))
      let size = max(minSize, idealSize)
      HStack(spacing: spacing) {
        ForEach(sorted, id: \.id) { p in
          Text(symbol(for: p))
            .font(.system(size: size))
            .foregroundStyle(p.color == .white ? .white : .black)
            .rotationEffect(rotatePieces ? .degrees(180) : .degrees(0))
            .frame(width: size, height: size)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.captureHighlight)
                .opacity(highlightPieceID == p.id ? 1 : 0)
            )
            .animation(.easeInOut(duration: 0.25), value: highlightPieceID)
        }
        if pointAdvantage > 0 {
          Text("+\(pointAdvantage)")
            .font(.system(size: size * 0.8, weight: .semibold))
            .foregroundColor(.white)
            .rotationEffect(rotatePieces ? .degrees(180) : .degrees(0))
            .padding(.leading, 4)
        }
        Spacer(minLength: 0)
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
    }
    .frame(height: 44)
  }

  private func sortedPieces() -> [Piece] { pieces.sorted { pieceValue($0) > pieceValue($1) } }
  private func pieceValue(_ p: Piece) -> Int {
    switch p.type { case .queen: return 9; case .rook: return 5; case .bishop, .knight: return 3; case .pawn: return 1; case .king: return 100 }
  }
  private func symbol(for p: Piece) -> String {
    switch p.type {
    case .king: return "♚"; case .queen: return "♛"; case .rook: return "♜"; case .bishop: return "♝"; case .knight: return "♞"; case .pawn: return "♟︎" }
  }
}
