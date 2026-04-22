import AppKit
import Observation
import SwiftUI

struct AppLogo: View {
  @Bindable var model: MemoryModel
  let bundle: String
  let size: CGFloat
  var body: some View {
    Group {
      if let icon = model.appIcon(bundle) {
        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
      } else {
        Image(systemName: bundle == "local.import" ? "photo" : "app.dashed").resizable()
          .scaledToFit().foregroundStyle(.secondary).padding(2)
      }
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}
