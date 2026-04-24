import AppKit
import Observation
import SwiftUI

struct QuietButton: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 9).frame(
      height: 30
    )
    .background(
      configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear,
      in: RoundedRectangle(cornerRadius: 7)
    )
    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
    .animation(
      reduceMotion ? nil : .spring(duration: 0.18, bounce: 0), value: configuration.isPressed
    )
    .contentShape(RoundedRectangle(cornerRadius: 7))
  }
}
