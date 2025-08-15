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
}
