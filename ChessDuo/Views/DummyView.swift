import SwiftUI

public struct DummyView: View {

  public var showSquare: Bool = false
  public var color: Color = Color.gray
  public var text: String?

  public var body: some View {
    ZStack {
      color
      Cross(color: Color.white.opacity(0.5))
      if showSquare {
        Cross(color: Color.black.opacity(0.5)).aspectRatio(1.0, contentMode: .fit)
      }
      Color.white.frame(width: 1)
      Color.white.frame(height: 1)
      Ellipse().opacity(0.3)
      if text != nil && text! != "" {
        Text(text!)
          .background(Color.white.cornerRadius(5).opacity(0.5))
      }
    }
  }
}

private func simplifiedDescription(description: String) -> String {
  let simpleDescription = description
    .replacingOccurrences(of: "ABLUI.", with: "")
    .replacingOccurrences(of: "#00000000", with: "")
    .replacingOccurrences(of: "ModifiedContent<", with: "")
  let firstComma = simpleDescription.firstIndex(of: ",") ?? simpleDescription.endIndex
  let firstParenthesis = simpleDescription.firstIndex(of: "(") ?? simpleDescription.endIndex
  let firstLessThan = simpleDescription.firstIndex(of: "<") ?? simpleDescription.endIndex
  let firstGreaterThan = simpleDescription.firstIndex(of: ">") ?? simpleDescription.endIndex
  let lastIndex = min(firstParenthesis, firstLessThan, firstGreaterThan, firstComma)
  return String(simpleDescription[..<lastIndex])
}


public struct Cross: View {
  public var color: Color
  public var body: some View {
    GeometryReader { geometry in
      Path { path in
        let width = geometry.size.width
        let height = geometry.size.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: height))
      }.fill(self.color)
      Path { path in
        let width = geometry.size.width
        let height = geometry.size.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width, y: height))
        path.move(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: height))
      }.stroke(self.color)
    }
  }
}
