//
//  HistorySliderView.swift
//  ChessDuo
//
//  Encapsulated slider to scrub through move history.
//

import SwiftUI

struct HistorySliderView: View {
  let currentIndex: Int?          // nil means live
  let totalMoves: Int             // moveHistory.count
  let onScrub: (Int?) -> Void     // callback with new index (nil == live)

  var body: some View {
    VStack(spacing: 4) {
      HStack {
        Text(label)
          .font(.caption)
          .padding(.leading, 4)
        Spacer(minLength: 0)
      }
      Slider(value: Binding<Double>(
        get: { Double(currentIndex ?? totalMoves) },
        set: { newVal in
          let idx = Int(newVal.rounded())
          let newHistory: Int? = (idx == totalMoves ? nil : max(0, min(idx, totalMoves)))
          if newHistory == currentIndex { return }
          onScrub(newHistory)
        }
      ), in: 0...Double(totalMoves), step: 1)
      .tint(AppColors.highlight)
      .padding(.horizontal, 4)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var label: String { currentIndex == nil ? "Live" : "Move \(currentIndex!) / \(totalMoves)" }
}

#if DEBUG
struct HistorySliderView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      HistorySliderView(currentIndex: 12, totalMoves: 40, onScrub: { _ in })
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
      HistorySliderView(currentIndex: nil, totalMoves: 40, onScrub: { _ in })
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
    }
  }
}
#endif
