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
          Text(p.symbol)
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
        if pointAdvantage != 0 { // show both positive and (future) negative if logic changes
          Text(String.localizedDelta(Int64(pointAdvantage)))
            .font(.system(size: size * 0.8, weight: .semibold))
            .foregroundColor(sortedPieces().first?.color == .white ? .white : .black)
            .rotationEffect(rotatePieces ? .degrees(180) : .degrees(0))
            .padding(.leading, 4)
        }
        Spacer(minLength: 0)
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
    }
    .frame(height: 44)
  }
  private func sortedPieces() -> [Piece] {
    pieces.sorted { a, b in
  // Use unified material value (king treated specially for ordering by inflating its score)
  let baseA = GameViewModel.materialValue(a)
  let baseB = GameViewModel.materialValue(b)
  let va = (a.type == .king ? 100 : baseA)
  let vb = (b.type == .king ? 100 : baseB)
      if va != vb { return va > vb }
      // Tie-breaker for same value (specifically bishop vs knight): bishops first
      if va == 3 {
        if a.type == b.type { return false }
        if a.type == .bishop && b.type == .knight { return true }
        if a.type == .knight && b.type == .bishop { return false }
      }
      // Stable-ish fallback: compare type raw ordering by defined priority
      return typePriority(a.type) < typePriority(b.type)
    }
  }
  private func typePriority(_ t: PieceType) -> Int {
    switch t {
    case .queen: return 0
    case .rook: return 1
    case .bishop: return 2
    case .knight: return 3
    case .pawn: return 4
    case .king: return 5
    }
  }
  // (Removed local symbol(for:); using Piece.symbol from central extension)
}
