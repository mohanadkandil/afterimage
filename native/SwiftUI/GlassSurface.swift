import SwiftUI

/// Keeps glass on the control layer, with an SDK and accessibility fallback.
struct GlassSurface: ViewModifier {
  var interactive = false
  var accented = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(.background, in: RoundedRectangle(cornerRadius: 10))
    } else {
      #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
          content.glassEffect(
            .regular.tint(accented ? Style.mint.opacity(0.18) : .clear).interactive(interactive),
            in: .rect(cornerRadius: 10))
        } else {
          material(content)
        }
      #else
        material(content)
      #endif
    }
  }

  private func material(_ content: Content) -> some View {
    content
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
          .allowsHitTesting(false)
      }
      .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
  }
}
