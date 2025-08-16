import SwiftUI

struct BoardView: View {
  let board: Board
  let perspective: PieceColor
  let myColor: PieceColor
  let sideToMove: PieceColor
  let inCheckCurrentSide: Bool
  let isCheckmatePosition: Bool
  let singleDevice: Bool
  let lastMove: Move?
  let historyIndex: Int?
  var disableInteraction: Bool = false
  var onAttemptInteraction: () -> Void = {}
  @Binding var selected: Square?
  let onMove: (Square, Square, Bool) -> Bool
  // Provides set of legal destinations for a given origin square (live position only)
  var legalMovesProvider: (Square) -> Set<Square> = { _ in [] }
  @Namespace private var pieceNamespace
  @StateObject private var gesture = BoardGestureController()

  var body: some View {
    GeometryReader { geo in
      let boardSide  = min(geo.size.width, geo.size.height)
      let rowArray   = rows()
      let colArray   = cols()
      let squareSize = boardSide / 8.0
      // Precompute active origin and its legal targets once per frame to avoid recomputing inside every square view.
      let activeOrigin: Square? = gesture.draggingFrom ?? selected
      let precomputedLegalTargets: Set<Square> = {
        guard let origin = activeOrigin else { return [] }
        return legalMovesProvider(origin)
      }()

      ZStack(alignment: .topLeading) {
        // Squares layer
        ForEach(Array(rowArray.enumerated()), id: \.offset) { rowIdx, rank in
          ForEach(Array(colArray.enumerated()), id: \.offset) { colIdx, file in
            squareView(rank: rank,
                       file: file,
                       rowIdx: rowIdx,
                       colIdx: colIdx,
                       squareSize: squareSize,
                       rowArray: rowArray,
                       colArray: colArray,
                       activeOrigin: activeOrigin,
                       legalTargets: precomputedLegalTargets)
          }
        }

        // Pieces layer (animated positions)
        ForEach(piecesOnBoard(), id: \.piece.id) { item in
          pieceView(item: item,
                    rowArray: rowArray,
                    colArray: colArray,
                    squareSize: squareSize)
        }
      }
      .frame(width: boardSide, height: boardSide)
      .contentShape(Rectangle())
      .animation(.easeInOut(duration: 0.35), value: board)
      .gesture(gesture.makeDragGesture(
        boardSide: boardSide,
        rowArray: rowArray,
        colArray: colArray,
        squareSize: squareSize,
        disableInteraction: disableInteraction,
        historyIndex: historyIndex,
        selected: $selected,
        sideToMove: sideToMove,
        myColor: myColor,
        singleDevice: singleDevice,
        onAttemptInteraction: onAttemptInteraction,
        boardPiece: { board.piece(at: $0) },
        canPickUp: { canPickUp(square: $0) },
        squareAtPoint: { point in square(at: point,
                                         boardSide: boardSide,
                                         rowArray: rowArray,
                                         colArray: colArray,
                                         squareSize: squareSize) },
        squareFrame: { sq in squareFrame(for: sq,
                                         rowArray: rowArray,
                                         colArray: colArray,
                                         squareSize: squareSize) },
        performMove: onMove))
      // Auto-clear any lingering selection when it becomes opponent's turn in connected mode.
      .onChange(of: sideToMove) { newSide in
        if !singleDevice && myColor != newSide {
          withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
        }
      }
    }
  }

  // MARK: - Square & Piece Subviews
  private func squareView(rank: Int,
                          file: Int,
                          rowIdx: Int,
                          colIdx: Int,
                          squareSize: CGFloat,
                          rowArray: [Int],
                          colArray: [Int],
                          activeOrigin: Square?,
                          legalTargets: Set<Square>) -> some View {
    let sq = Square(file: file, rank: rank)
    let piece = board.piece(at: sq)
    let kingInCheckHighlight = inCheckCurrentSide && piece?.type == .king && piece?.color == sideToMove
    let dragHighlight: Bool = {
      guard let from = gesture.draggingFrom else { return false }
      if from == sq { return true }
      if let target = gesture.dragTarget, target == sq { return true }
      return false
    }()
    // Determine coordinate labels
    // Rank numbers should appear on the visually leftmost column.
    // For white perspective, that's file == 0 (column a). For black perspective (connected mode), that's file == 7.
    let blackPerspective = (perspective == .black && !singleDevice)
    let rankLabelFile = blackPerspective ? 7 : 0
    let showRankLabel = file == rankLabelFile
    // File letters: normally on white's home rank (rank == 0). If viewing from black perspective in connected mode (not single-device), place on black's home rank (rank == 7).
    // File letters adapt similarly (already defined blackPerspective above)
    let fileLabelRank = blackPerspective ? 7 : 0
    let showFileLabel = rank == fileLabelRank
    let rankNumber = rank + 1
    let fileLetter = String(UnicodeScalar("a".unicodeScalars.first!.value + UInt32(file))!)
  // Use precomputed legalTargets for current active origin; avoids recalculating per square.
  let showIndicator = activeOrigin != nil && legalTargets.contains(sq)
    // Distinguish capture vs quiet move
    let isCaptureIndicator: Bool = showIndicator && board.piece(at: sq) != nil && board.piece(at: activeOrigin!)?.color != board.piece(at: sq)?.color
    // Square brightness for color choice
    let isDarkSquare = ((sq.file + sq.rank) % 2 == 0)
    let quietColor = isDarkSquare ? AppColors.moveIndicatorQuietOnDark : AppColors.moveIndicatorQuietOnLight
    let captureColor = isDarkSquare ? AppColors.moveIndicatorCaptureOnDark : AppColors.moveIndicatorCaptureOnLight

    return ZStack {
      SquareView(
        square: sq,
        piece: nil,
        isKingInCheck: kingInCheckHighlight,
        isKingCheckmated: isCheckmatePosition && kingInCheckHighlight,
        rotateForOpponent: false,
        lastMoveHighlight: isLastMoveSquare(sq) || dragHighlight
      )
      // Legal move indicator layer
      if showIndicator {
        GeometryReader { g in
          let size = min(g.size.width, g.size.height)
          if isCaptureIndicator {
            // Filled larger circle for capture squares (piece present)
            Circle()
              .fill(captureColor)
              .frame(width: size * 0.8, height: size * 0.8)
              .position(x: size / 2, y: size / 2)
              .transition(.scale.combined(with: .opacity))
          } else {
            // Dot indicator for quiet moves
            Circle()
              .fill(quietColor)
              .frame(width: size * 0.28, height: size * 0.28)
              .position(x: size / 2, y: size / 2)
              .transition(.scale.combined(with: .opacity))
          }
        }
        // Skip animation while an active drag is in progress to reduce frame overhead.
        .if(!gesture.dragActivated) { view in
          view.animation(.easeInOut(duration: 0.18), value: showIndicator)
        }
        .accessibilityHidden(true)
      }
      // Overlay coordinate labels
      GeometryReader { g in
        let lightGray = AppColors.coordLight
        let darkGray = AppColors.coordDark
        let isDarkSquare = ((sq.file + sq.rank) % 2 == 0)
        // Contrast: use opposite tone
        let labelColor = isDarkSquare ? lightGray : darkGray
        ZStack {
          if showRankLabel {
            Text("\(rankNumber)")
              .font(AppFonts.boardCoordinate)
              .foregroundColor(labelColor)
              .position(x: g.size.width * 0.15, y: g.size.height * 0.18)
              .accessibilityHidden(true)
          }
          if showFileLabel {
            Text(fileLetter)
              .font(AppFonts.boardCoordinate)
              .foregroundColor(labelColor)
              .position(x: g.size.width * 0.82, y: g.size.height * 0.82)
              .accessibilityHidden(true)
          }
        }
      }
    }
    .frame(width: squareSize, height: squareSize)
    .position(x: CGFloat(colIdx) * squareSize + squareSize / 2,
              y: CGFloat(rowIdx) * squareSize + squareSize / 2)
    .contentShape(Rectangle())
  }

  private func pieceView(item: (square: Square, piece: Piece),
                         rowArray: [Int],
                         colArray: [Int],
                         squareSize: CGFloat) -> some View {
    let rowIdx = rowArray.firstIndex(of: item.square.rank) ?? 0
    let colIdx = colArray.firstIndex(of: item.square.file) ?? 0
    return ZStack {
      let showSelectionRing = selected == item.square && !(gesture.dragActivated && gesture.draggingFrom == item.square)
      if showSelectionRing {
        RoundedRectangle(cornerRadius: 6)
          .stroke(AppColors.highlightLight, lineWidth: 2)
          .padding(2)
      }
      Text(symbol(for: item.piece))
        .font(.system(size: squareSize * 0.75))
        .foregroundColor(item.piece.color == .white ? AppColors.pieceWhite : AppColors.pieceBlack)
        // In single-device (hot-seat) mode rotate the TOP side pieces so they face that player.
        // Top side color is always the opposite of perspective.
        .rotationEffect(singleDevice && item.piece.color == perspective.opposite ? .degrees(180) : .degrees(0))
        .scaleEffect(gesture.dragActivated && gesture.draggingFrom == item.square ? 3.0 : 1.0)
        .offset(y: pieceLiftOffset(for: item))
        .shadow(color: gesture.dragActivated && gesture.draggingFrom == item.square ? Color.black.opacity(0.4) : Color.clear,
                radius: 8, x: 0, y: 4)
    }
    .frame(width: squareSize, height: squareSize)
    .position(
      x: gesture.positionForPiece(item.square,
                                  defaultPos: CGFloat(colIdx) * squareSize + squareSize / 2,
                                  squareSize: squareSize,
                                  axis: .x),
      y: gesture.positionForPiece(item.square,
                                  defaultPos: CGFloat(rowIdx) * squareSize + squareSize / 2,
                                  squareSize: squareSize,
                                  axis: .y)
    )
    // Avoid matchedGeometryEffect on the actively dragged piece to reduce per-frame layout cost.
    .if(!(gesture.dragActivated && gesture.draggingFrom == item.square)) { view in
      view.matchedGeometryEffect(id: item.piece.id, in: pieceNamespace)
    }
    .zIndex(gesture.zIndexForPiece(item.square, selected: selected))
    .contentShape(Rectangle())
  }

  private func pieceLiftOffset(for item: (square: Square, piece: Piece)) -> CGFloat {
    guard gesture.dragActivated && gesture.draggingFrom == item.square else { return 0 }
    let magnitude = 50.0
  // In single-device mode the top side pieces (perspective.opposite) lift downward visually when picked up
  if singleDevice && item.piece.color == perspective.opposite { return magnitude }
    return -magnitude
  }

  // MARK: - Drag Gesture now provided by BoardGestureController

  // Tap & Drag helpers moved into BoardGestureController
  // finalizeDrag & clearAfterTap moved into BoardGestureController

  // Drag helpers
  // MARK: - Computation Helpers
  // Axis, position, adjusted center & z-index helpers now live in BoardGestureController

  private func squareFrame(for sq: Square,
                           rowArray: [Int],
                           colArray: [Int],
                           squareSize: CGFloat) -> CGRect? {
    guard let rowIdx = rowArray.firstIndex(of: sq.rank),
          let colIdx = colArray.firstIndex(of: sq.file) else { return nil }
    let origin = CGPoint(x: CGFloat(colIdx) * squareSize,
                         y: CGFloat(rowIdx) * squareSize)
    return CGRect(origin: origin, size: CGSize(width: squareSize, height: squareSize))
  }

  private func canPickUp(square: Square) -> Bool {
    if singleDevice {
      if let p = board.piece(at: square), p.color == sideToMove { return true }
      return false
    } else {
      if let p = board.piece(at: square), p.color == myColor, myColor == sideToMove { return true }
      return false
    }
  }

  private func rows() -> [Int] {
    perspective == .white ? Array((0..<8).reversed()) : Array(0..<8)
  }

  private func cols() -> [Int] {
    perspective == .white ? Array(0..<8) : Array((0..<8).reversed())
  }

  private func piecesOnBoard() -> [(square: Square, piece: Piece)] {
    var list: [(Square, Piece)] = []
    for rank in 0..<8 {
      for file in 0..<8 {
        let sq = Square(file: file, rank: rank)
        if let p = board.piece(at: sq) { list.append((sq, p)) }
      }
    }
    return list
  }

  private func symbol(for p: Piece) -> String {
    switch p.type {
    case .king: return "♚"
    case .queen: return "♛"
    case .rook: return "♜"
    case .bishop: return "♝"
    case .knight: return "♞"
    case .pawn: return "♟︎"
    }
  }

  private func square(at point: CGPoint,
                      boardSide: CGFloat,
                      rowArray: [Int],
                      colArray: [Int],
                      squareSize: CGFloat) -> Square? {
    guard point.x >= 0, point.y >= 0,
          point.x < boardSide, point.y < boardSide else { return nil }
    let colIdx = Int(point.x / squareSize)
    let rowIdx = Int(point.y / squareSize)
    guard rowIdx >= 0 && rowIdx < rowArray.count && colIdx >= 0 && colIdx < colArray.count else { return nil }
    let rank = rowArray[rowIdx]
    let file = colArray[colIdx]
    return Square(file: file, rank: rank)
  }

  private func activateDrag(at point: CGPoint,
                            boardSide: CGFloat,
                            rowArray: [Int],
                            colArray: [Int],
                            squareSize: CGFloat) {
    gesture.activateDrag(at: point) { sq in squareFrame(for: sq, rowArray: rowArray, colArray: colArray, squareSize: squareSize) }
  }

  private func cancelCurrentDrag() {
    gesture.cancelCurrentDrag()
  }

  private func resetGestureState() {
    gesture.resetGestureState()
  }

  private func isLastMoveSquare(_ sq: Square) -> Bool {
    guard let mv = lastMove else { return false }
    return mv.from == sq || mv.to == sq
  }
}

// MARK: - View helpers
private extension View {
  @ViewBuilder
  func `if`<Content: View>(_ condition: @autoclosure () -> Bool, transform: (Self) -> Content) -> some View {
    if condition() { transform(self) } else { self }
  }
}
