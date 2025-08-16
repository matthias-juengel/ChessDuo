import SwiftUI

/// Encapsulates drag/gesture-related state and helper logic for the chess board.
/// BoardView owns an instance (@StateObject) and delegates gesture mutations here
/// to keep the view struct slimmer and focused on layout.
final class BoardGestureController: ObservableObject {
  // MARK: - Published Drag State
  @Published var draggingFrom: Square? = nil
  @Published var dragLocation: CGPoint? = nil
  @Published var dragTarget: Square? = nil
  @Published var dragOffsetFromCenter: CGSize? = nil
  @Published var pendingDragFrom: Square? = nil
  @Published var dragStartPoint: CGPoint? = nil
  @Published var dragActivated: Bool = false
  @Published var gestureInitialSelected: Square? = nil
  @Published var gestureHistoryIndexAtStart: Int? = nil
  @Published var blockedGesture: Bool = false

  // Last location we published (for throttling)
  private var lastPublishedDragPoint: CGPoint? = nil
  // Minimum movement (in points) required to republish dragLocation to cut down on UI invalidations.
  private let dragPublishThreshold: CGFloat = 2.0

  // Not published: internal scheduling work item
  var dragHoldWorkItem: DispatchWorkItem? = nil

  // MARK: - Axis Support
  enum Axis { case x, y }

  // MARK: - State Transitions
  func activateDrag(at point: CGPoint, frameProvider: (Square) -> CGRect?) {
    guard !dragActivated, let sq = pendingDragFrom else { return }
    draggingFrom = sq
    dragActivated = true
    if let frame = frameProvider(sq) {
      let center = CGPoint(x: frame.midX, y: frame.midY)
      dragOffsetFromCenter = CGSize(width: center.x - point.x, height: center.y - point.y)
    }
  }

  func cancelCurrentDrag() {
    dragHoldWorkItem?.cancel(); dragHoldWorkItem = nil
    pendingDragFrom = nil
    draggingFrom = nil
    dragLocation = nil
    dragTarget = nil
    dragOffsetFromCenter = nil
    dragActivated = false
  }

  func resetGestureState() {
    cancelCurrentDrag()
    dragStartPoint = nil
    gestureInitialSelected = nil
    gestureHistoryIndexAtStart = nil
  }

  func clearAfterTap() {
    pendingDragFrom = nil
    draggingFrom = nil
    dragLocation = nil
    dragTarget = nil
    dragOffsetFromCenter = nil
    dragActivated = false
    dragStartPoint = nil
    gestureInitialSelected = nil
  }

  func finalizeDrag(performedMove: Bool,
                    origin: Square,
                    frameProvider: (Square) -> CGRect?,
                    animation: (()->Void) -> Void = { withAnimation(.spring(response: 0.45, dampingFraction: 0.72), $0) },
                    completionDelay: TimeInterval = 0.46) {
    if !performedMove {
      if let originFrame = frameProvider(origin) {
        let center = CGPoint(x: originFrame.midX, y: originFrame.midY)
        animation { [weak self] in
          guard let self else { return }
          self.dragActivated = false
          if let off = self.dragOffsetFromCenter {
            self.dragLocation = CGPoint(x: center.x - off.width, y: center.y - off.height)
          } else {
            self.dragLocation = center
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) { [weak self] in
          guard let self else { return }
          if self.draggingFrom == origin {
            self.draggingFrom = nil
            self.dragLocation = nil
            self.dragTarget = nil
            self.dragOffsetFromCenter = nil
          }
        }
      } else {
        // Could not compute frame; hard reset
        draggingFrom = nil
        dragLocation = nil
        dragTarget = nil
        dragOffsetFromCenter = nil
        dragActivated = false
      }
    } else {
      draggingFrom = nil
      dragLocation = nil
      dragTarget = nil
      dragOffsetFromCenter = nil
      dragActivated = false
    }
    pendingDragFrom = nil
    dragStartPoint = nil
    gestureInitialSelected = nil
    gestureHistoryIndexAtStart = nil
    blockedGesture = false
  }

  // MARK: - Computation Helpers
  func positionForPiece(_ sq: Square,
                        defaultPos: CGFloat,
                        squareSize: CGFloat,
                        axis: Axis) -> CGFloat {
    guard let from = draggingFrom, from == sq, let dragLocation else { return defaultPos }
    var pos: CGFloat = (axis == .x ? dragLocation.x : dragLocation.y)
    if let off = dragOffsetFromCenter { pos += (axis == .x ? off.width : off.height) }
    let limit = squareSize * 8
    return min(max(pos, 0), limit)
  }

  func adjustedDragCenter(rawPoint: CGPoint, squareSize: CGFloat) -> CGPoint {
    var x = rawPoint.x
    var y = rawPoint.y
    if let off = dragOffsetFromCenter { x += off.width; y += off.height }
    let limit = squareSize * 8
    x = min(max(x, 0), limit)
    y = min(max(y, 0), limit)
    return CGPoint(x: x, y: y)
  }

  func zIndexForPiece(_ sq: Square, selected: Square?) -> Double {
    if draggingFrom == sq { return 500 }
    if selected == sq { return 100 }
    return 10
  }

  // MARK: - High-level Interaction Helpers
  /// Handles a tap (or tap-like release) on a target square, updating selection or attempting a move via closure.
  /// - Parameters:
  ///   - target: Square tapped.
  ///   - selected: Binding to currently selected square.
  ///   - boardPiece: closure returning piece at a square.
  ///   - sideToMove: current side to move.
  ///   - myColor: local player's color when multiplayer.
  ///   - singleDevice: whether playing single-device (both sides local).
  ///   - performMove: closure to attempt a move when appropriate.
  func handleTap(target: Square,
                 selected: inout Square?,
                 boardPiece: (Square) -> Piece?,
                 sideToMove: PieceColor,
                 myColor: PieceColor,
                 singleDevice: Bool,
                 performMove: (Square, Square, Bool) -> Bool) {
    // In connected (two-device) mode, block any new selections or move attempts when it's not our turn.
    // Allow deselecting an already-selected piece (tapping it again) for UX cleanliness.
    if !singleDevice && myColor != sideToMove {
      if let sel = selected, sel == target {
        withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
      }
      return
    }
    if let sel = selected {
      if sel == target {
        if let initial = gestureInitialSelected, initial == sel {
          withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
        }
        return
      }
      let ownershipColor = singleDevice ? sideToMove : myColor // (myColor == sideToMove ensured above for connected mode)
      if let p = boardPiece(target), p.color == ownershipColor {
  withAnimation(.easeInOut(duration: 0.18)) { selected = target }
  Haptics.trigger(.pieceSelected)
      } else {
  let moved = performMove(sel, target, singleDevice)
  if moved { Haptics.trigger(.moveSuccess) }
        withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
      }
      return
    }
    // No selection yet
    let ownershipColor = singleDevice ? sideToMove : myColor // safe: for connected mode we already verified turn ownership
    if let p = boardPiece(target), p.color == ownershipColor {
  withAnimation(.easeInOut(duration: 0.18)) { selected = target }
  Haptics.trigger(.pieceSelected)
    }
  }

  /// Handles releasing a drag onto a target square.
  func handleDragRelease(origin: Square,
                         release: Square,
                         selected: inout Square?,
                         boardPiece: (Square) -> Piece?,
                         sideToMove: PieceColor,
                         myColor: PieceColor,
                         singleDevice: Bool,
                         performMove: (Square, Square, Bool) -> Bool) -> Bool {
    var performedMove = false
    if origin == release {
  if selected != origin { withAnimation(.easeInOut(duration: 0.18)) { selected = origin }; Haptics.trigger(.pieceReSelected) }
    } else {
      let ownershipColor = singleDevice ? sideToMove : myColor
      if let p = boardPiece(release), p.color == ownershipColor {
  withAnimation(.easeInOut(duration: 0.18)) { selected = release }
  Haptics.trigger(.pieceSelected)
      } else if selected == origin {
        let success = performMove(origin, release, singleDevice)
        if success {
          withAnimation(.easeInOut(duration: 0.18)) { selected = nil }
          Haptics.trigger(.moveSuccess)
          performedMove = true
        }
      } else {
  withAnimation(.easeInOut(duration: 0.18)) { selected = origin }
  Haptics.trigger(.pieceReSelected)
      }
    }
    return performedMove
  }

  // MARK: - Gesture Factory
  /// Builds the DragGesture used by the board, injecting required closures/data.
  func makeDragGesture(boardSide: CGFloat,
                       rowArray: [Int],
                       colArray: [Int],
                       squareSize: CGFloat,
                       disableInteraction: Bool,
                       historyIndex: Int?,
                       selected: Binding<Square?>,
                       sideToMove: PieceColor,
                       myColor: PieceColor,
                       singleDevice: Bool,
                       onAttemptInteraction: @escaping () -> Void,
                       boardPiece: @escaping (Square) -> Piece?,
                       canPickUp: @escaping (Square) -> Bool,
                       squareAtPoint: @escaping (CGPoint) -> Square?,
                       squareFrame: @escaping (Square) -> CGRect?,
                       performMove: @escaping (Square, Square, Bool) -> Bool) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { [weak self] value in
        guard let self else { return }
        onAttemptInteraction()
        if self.dragStartPoint == nil {
          self.dragStartPoint = value.location
          self.gestureInitialSelected = selected.wrappedValue
          self.gestureHistoryIndexAtStart = historyIndex
          self.blockedGesture = disableInteraction || historyIndex != nil
        }
        guard !self.blockedGesture else { return }
        if self.gestureHistoryIndexAtStart != historyIndex { self.blockedGesture = true; self.cancelCurrentDrag(); return }
        guard !disableInteraction else { return }

        let point = value.location
        // Lazy pick-up scheduling
        if self.pendingDragFrom == nil && !self.dragActivated, let sq = squareAtPoint(point), canPickUp(sq) {
          self.pendingDragFrom = sq
          selected.wrappedValue = sq
          // Fire haptic for selection initiated via drag (mirrors tap behavior)
          Haptics.trigger(.pieceSelected)
          let wi = DispatchWorkItem { self.activateDrag(at: point, frameProvider: squareFrame) }
          self.dragHoldWorkItem?.cancel()
          self.dragHoldWorkItem = wi
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: wi)
        }
        // Throttle dragLocation publishes to reduce layout churn.
        if let last = self.lastPublishedDragPoint {
          let dx = point.x - last.x
            let dy = point.y - last.y
            if (dx*dx + dy*dy) >= dragPublishThreshold * dragPublishThreshold {
              self.dragLocation = point
              self.lastPublishedDragPoint = point
            }
        } else {
          self.dragLocation = point
          self.lastPublishedDragPoint = point
        }
        // Movement threshold
        if !self.dragActivated, let start = self.dragStartPoint, self.pendingDragFrom != nil {
          let dx = point.x - start.x
          let dy = point.y - start.y
          let dist = sqrt(dx*dx + dy*dy)
          let movementThreshold = max(8, squareSize * 0.08)
          if dist > movementThreshold {
            self.activateDrag(at: point, frameProvider: squareFrame)
          }
        }
        if self.dragActivated {
          let pieceCenter = self.adjustedDragCenter(rawPoint: point, squareSize: squareSize)
          self.dragTarget = squareAtPoint(pieceCenter)
        } else {
          self.dragTarget = nil
        }
      }
      .onEnded { [weak self] value in
        guard let self else { return }
        guard !disableInteraction else { return }
        if self.blockedGesture { self.resetGestureState(); return }
        let point = value.location
        let pieceCenter = self.adjustedDragCenter(rawPoint: point, squareSize: squareSize)
        let releasedSquare = squareAtPoint(pieceCenter)
        self.dragHoldWorkItem?.cancel(); self.dragHoldWorkItem = nil
  self.lastPublishedDragPoint = nil
        if !self.dragActivated {
          if let target = releasedSquare { self.handleTap(target: target,
                                                          selected: &selected.wrappedValue,
                                                          boardPiece: boardPiece,
                                                          sideToMove: sideToMove,
                                                          myColor: myColor,
                                                          singleDevice: singleDevice,
                                                          performMove: performMove) }
          self.clearAfterTap()
          return
        }
        guard let origin = self.draggingFrom else { return }
        let performedMove = releasedSquare.map { release in
          self.handleDragRelease(origin: origin,
                                 release: release,
                                 selected: &selected.wrappedValue,
                                 boardPiece: boardPiece,
                                 sideToMove: sideToMove,
                                 myColor: myColor,
                                 singleDevice: singleDevice,
                                 performMove: performMove)
        } ?? false
        self.finalizeDrag(performedMove: performedMove,
                          origin: origin,
                          frameProvider: squareFrame)
      }
  }
}
