import SwiftUI

struct LittRootView: View {
  @Bindable var model: MemoryModel
  let setupChanged: (Bool) -> Void
  var body: some View {
    Group {
      if model.showOnboarding {
        OnboardingView(model: model)
          .alert(
            "Couldn’t start recording",
            isPresented: Binding(
              get: { model.error != nil }, set: { if !$0 { model.error = nil } })
          ) {
            Button("OK") { model.error = nil }
          } message: {
            Text(model.error ?? "")
          }
      } else {
        LittView(model: model)
      }
    }
    .task { model.start() }
    .onChange(of: model.showOnboarding) { _, value in setupChanged(value) }
  }
}
