import AppKit
import Observation
import SwiftUI

struct QuietButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 9).frame(
      height: 30
    )
    .background(
      configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear,
      in: RoundedRectangle(cornerRadius: 7)
    )
    .contentShape(RoundedRectangle(cornerRadius: 7))
  }
}
