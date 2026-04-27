import SwiftUI

struct SettingsSelection: ViewModifier {
  let selected: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if selected {
      content.modifier(GlassSurface(interactive: true))
    } else {
      content
    }
  }
}
