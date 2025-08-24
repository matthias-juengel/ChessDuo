//
//  GameViewModel+HistoryNavigation.swift
//  Adds lightweight view-only history navigation (undo/redo) separate from revert logic.
//
//  Undo/Redo here only manipulates `historyIndex` to show prior board states. It does NOT
//  mutate moveHistory or engine state and requires explicit confirmation via the existing
//  revert button to truncate history.
//
import Foundation

extension GameViewModel {
  /// Returns the index currently being viewed (historyIndex if set, else the live movesMade).
  private var viewedIndex: Int { historyIndex ?? movesMade }

  /// Whether we can step backward in history view (there is at least one prior state).
  var canUndoView: Bool { viewedIndex > 0 }

  /// Whether we can step forward (only meaningful if we are currently in history view and not at live state).
  var canRedoView: Bool { if let idx = historyIndex { return idx < movesMade } else { return false } }

  /// Step one move back in viewed history (enters history view if coming from live state).
  /// This is a local-only exploration and should NOT broadcast history view messages.
  func viewHistoryBack() {
    let current = viewedIndex
    guard current > 0 else { return }
    let newIndex = current - 1
    // Always enter history view when stepping back (newIndex is < movesMade when coming from live).
    historyIndex = newIndex
  }

  /// Step one move forward in viewed history. If we reach movesMade we exit history view.
  /// Local-only exploration; suppress broadcast.
  func viewHistoryForward() {
    guard let idx = historyIndex else { return } // Only meaningful while in history view.
    let newIndex = idx + 1
    guard newIndex <= movesMade else { return }
    if newIndex == movesMade {
      historyIndex = nil
    } else {
      historyIndex = newIndex
    }
  }

  /// Jump directly to the beginning of the game (index 0) in history view (long-press undo).
  func jumpToHistoryStart() {
    guard movesMade > 0 else { return }
    // Only act if not already at start.
    if historyIndex != 0 { historyIndex = 0 }
  }

  /// Jump directly back to the live state (long-press redo).
  func jumpToLiveState() {
    guard historyIndex != nil else { return }
    historyIndex = nil
  }
}
