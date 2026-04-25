import SwiftUI

struct SetupButtonStyle: ButtonStyle {
  var primary = true
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, 20).frame(height: 40)
      .foregroundStyle(primary ? Color(red: 0.08, green: 0.13, blue: 0.12) : Color.primary)
      .background(
        primary ? Style.mint : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)
      )
      .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
  }
}
