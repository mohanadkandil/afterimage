import SwiftUI

struct AfterimageRootView: View {
  @Bindable var model: MemoryModel
  let setupChanged: (Bool) -> Void
  let settingsChanged: (Bool) -> Void
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
        AfterimageView(model: model)
      }
    }
    .task { model.start() }
    .onChange(of: model.showSettings) { _, value in settingsChanged(value) }
    .onChange(of: model.showOnboarding) { _, value in setupChanged(value) }
  }
}
