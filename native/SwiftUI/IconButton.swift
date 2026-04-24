import AppKit
import Observation
import SwiftUI

struct IconButton: View {
  let symbol: String
  let title: String
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovered = false
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(
        width: 30, height: 30
      ).background(hovered ? Style.faint : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain).foregroundStyle(.secondary).onHover { value in
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovered = value }
    }.help(title)
    .accessibilityLabel(title)
  }
}
