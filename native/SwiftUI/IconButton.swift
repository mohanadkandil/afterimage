import AppKit
import Observation
import SwiftUI

struct IconButton: View {
  let symbol: String
  let title: String
  let action: () -> Void
  @State private var hovered = false
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(
        width: 30, height: 30
      ).background(hovered ? Style.faint : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain).foregroundStyle(.secondary).onHover { hovered = $0 }.help(title)
    .accessibilityLabel(title)
  }
}
