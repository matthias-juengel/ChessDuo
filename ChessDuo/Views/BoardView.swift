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
  @Namespace private var pieceNamespace
  @StateObject private var gesture = BoardGestureController()

  var body: some View {
    GeometryReader { geo in
      let boardSide  = min(geo.size.width, geo.size.height)
      let rowArray   = rows()
      let colArray   = cols()
      let squareSize = boardSide / 8.0

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
                       colArray: colArray)
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
      .gesture(dragGesture(boardSide: boardSide,
                           rowArray: rowArray,
                           colArray: colArray,
                           squareSize: squareSize))
    }
  }

  // MARK: - Square & Piece Subviews
  private func squareView(rank: Int,
                          file: Int,
                          rowIdx: Int,
                          colIdx: Int,
                          squareSize: CGFloat,
                          rowArray: [Int],
                          colArray: [Int]) -> some View {
    let sq = Square(file: file, rank: rank)
    let piece = board.piece(at: sq)
    let kingInCheckHighlight = inCheckCurrentSide && piece?.type == .king && piece?.color == sideToMove
    let dragHighlight: Bool = {
  guard let from = gesture.draggingFrom else { return false }
      if from == sq { return true }
  if let target = gesture.dragTarget, target == sq { return true }
      return false
    }()
    return SquareView(
      square: sq,
      piece: nil,
      isSelected: selected == sq,
      isKingInCheck: kingInCheckHighlight,
      isKingCheckmated: isCheckmatePosition && kingInCheckHighlight,
      rotateForOpponent: false,
      lastMoveHighlight: isLastMoveSquare(sq) || dragHighlight
    )
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
          .stroke(Color.white, lineWidth: 2)
          .padding(2)
          .shadow(color: .white.opacity(0.6), radius: 4)
      }
      Text(symbol(for: item.piece))
        .font(.system(size: squareSize * 0.75))
        .foregroundColor(item.piece.color == .white ? .white : .black)
        .rotationEffect(singleDevice && item.piece.color == .black ? .degrees(180) : .degrees(0))
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
    .matchedGeometryEffect(id: item.piece.id, in: pieceNamespace)
  .zIndex(gesture.zIndexForPiece(item.square, selected: selected))
    .contentShape(Rectangle())
  }

  private func pieceLiftOffset(for item: (square: Square, piece: Piece)) -> CGFloat {
  guard gesture.dragActivated && gesture.draggingFrom == item.square else { return 0 }
    let magnitude = 50.0
    if singleDevice && item.piece.color == .black { return magnitude }
    return -magnitude
  }

  // MARK: - Drag Gesture
  private func dragGesture(boardSide: CGFloat,
                           rowArray: [Int],
                           colArray: [Int],
                           squareSize: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        onAttemptInteraction()

        // Establish gesture baseline on first change
        if gesture.dragStartPoint == nil {
          gesture.dragStartPoint = value.location
          gesture.gestureInitialSelected = selected
          gesture.gestureHistoryIndexAtStart = historyIndex
          gesture.blockedGesture = disableInteraction || historyIndex != nil
        }
        guard !gesture.blockedGesture else { return }
        if gesture.gestureHistoryIndexAtStart != historyIndex { gesture.blockedGesture = true; gesture.cancelCurrentDrag(); return }
        guard !disableInteraction else { return }

        let point = value.location

        // Lazy pick-up scheduling (hold or slight move)
        if gesture.pendingDragFrom == nil && !gesture.dragActivated, let sq = square(at: point,
                                                                    boardSide: boardSide,
                                                                    rowArray: rowArray,
                                                                    colArray: colArray,
                                                                    squareSize: squareSize),
           canPickUp(square: sq) {
          gesture.pendingDragFrom = sq
          selected = sq
          let wi = DispatchWorkItem { activateDrag(at: point,
                                                   boardSide: boardSide,
                                                   rowArray: rowArray,
                                                   colArray: colArray,
                                                   squareSize: squareSize) }
          gesture.dragHoldWorkItem?.cancel()
          gesture.dragHoldWorkItem = wi
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: wi)
        }

        gesture.dragLocation = point

        // Movement threshold promotes to active drag early
  if !gesture.dragActivated, let start = gesture.dragStartPoint, gesture.pendingDragFrom != nil {
          let dx = point.x - start.x
          let dy = point.y - start.y
          let dist = sqrt(dx*dx + dy*dy)
          let movementThreshold = max(8, squareSize * 0.08)
          if dist > movementThreshold {
            activateDrag(at: point,
                         boardSide: boardSide,
                         rowArray: rowArray,
                         colArray: colArray,
                         squareSize: squareSize)
          }
        }

        // Update target square while dragging
        if gesture.dragActivated {
          let pieceCenter = gesture.adjustedDragCenter(rawPoint: point, squareSize: squareSize)
          gesture.dragTarget = square(at: pieceCenter,
                               boardSide: boardSide,
                               rowArray: rowArray,
                               colArray: colArray,
                               squareSize: squareSize)
        } else {
          gesture.dragTarget = nil
        }
      }
      .onEnded { value in
        guard !disableInteraction else { return }
        if gesture.blockedGesture { gesture.resetGestureState(); return }

        let point = value.location
        let pieceCenter = gesture.adjustedDragCenter(rawPoint: point, squareSize: squareSize)
        let releasedSquare = square(at: pieceCenter,
                                     boardSide: boardSide,
                                     rowArray: rowArray,
                                     colArray: colArray,
                                     squareSize: squareSize)
        gesture.dragHoldWorkItem?.cancel(); gesture.dragHoldWorkItem = nil

        // Tap without drag activation
        if !gesture.dragActivated {
          if let target = releasedSquare { handleTap(target: target) }
          gesture.clearAfterTap()
          return
        }

        guard let origin = gesture.draggingFrom else { return }
        let performedMove = releasedSquare.map { release in
          handleDragRelease(origin: origin,
                            release: release,
                            squareSize: squareSize,
                            rowArray: rowArray,
                            colArray: colArray)
        } ?? false
        gesture.finalizeDrag(performedMove: performedMove,
                             origin: origin,
                             frameProvider: { sq in squareFrame(for: sq, rowArray: rowArray, colArray: colArray, squareSize: squareSize) })
      }
  }

  // Tap & Drag helpers
  private func handleTap(target: Square) {
    if let sel = selected {
      if sel == target {
  if let initial = gesture.gestureInitialSelected, initial == sel {
          withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
        }
        return
      }
      let ownershipColor = singleDevice ? sideToMove : myColor
      if let p = board.piece(at: target), p.color == ownershipColor {
        withAnimation(.easeInOut(duration: 0.18)) { selected = target }
      } else {
        _ = onMove(sel, target, singleDevice)
        withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
      }
      return
    }
    // No selection yet
    let ownershipColor = singleDevice ? sideToMove : myColor
    if let p = board.piece(at: target), p.color == ownershipColor {
      withAnimation(.easeInOut(duration: 0.18)) { selected = target }
    }
  }
  private func handleDragRelease(origin: Square,
                                 release: Square,
                                 squareSize: CGFloat,
                                 rowArray: [Int],
                                 colArray: [Int]) -> Bool {
    var performedMove = false
    if origin == release {
      if selected != origin { withAnimation(.easeInOut(duration: 0.18)) { selected = origin } }
    } else {
      let ownershipColor = singleDevice ? sideToMove : myColor
      if let p = board.piece(at: release), p.color == ownershipColor {
        withAnimation(.easeInOut(duration: 0.18)) { selected = release }
      } else if selected == origin {
        let success = onMove(origin, release, singleDevice)
        if success {
          withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
          performedMove = true
        }
      } else {
        withAnimation(.easeInOut(duration: 0.18)) { selected = origin }
      }
    }
    return performedMove
  }
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
