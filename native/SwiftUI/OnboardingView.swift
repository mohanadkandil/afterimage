import SwiftUI

struct OnboardingView: View {
  @Bindable var model: MemoryModel
  @State private var step = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let titles = ["Find your way back.", "You choose what stays.", "Ready when you are."]
  private let descriptions = [
    "Return to something you saw. Screenshots and searchable text stay on this Mac.",
    "Screen Recording permission lets Afterimage save your display. Capture stays paused until you press Record.",
    "Press Start recording to begin saving moments and open your timeline. You can pause at any time.",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        ForEach(0..<3) { index in
          Capsule().fill(index == step ? Style.mint : Color.secondary.opacity(0.2))
            .frame(width: index == step ? 24 : 8, height: 4)
        }
        Spacer()
        Text("\(step + 1) of 3").font(.caption).foregroundStyle(.secondary)
      }.accessibilityElement(children: .ignore).accessibilityLabel(
        "Introduction, step \(step + 1) of 3")
      Spacer()
      VStack(alignment: .leading, spacing: 18) {
        OnboardingIllustration(step: step)
        Text(titles[step]).font(.system(size: 30, weight: .semibold)).tracking(-0.7)
        Text(descriptions[step]).font(.system(size: 14)).foregroundStyle(.secondary)
          .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        if step == 1 {
          HStack(spacing: 8) {
            Image(systemName: model.state.permission ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(model.state.permission ? Style.mint : Color.secondary)
            Text(model.state.permission ? "Permission granted" : "Permission not granted")
              .font(.caption).foregroundStyle(.secondary)
          }
          if !model.state.permission {
            Button("Allow screen capture…") {
              Task {
                await model.action("requestPermission")
                await model.refresh()
              }
            }.buttonStyle(SetupButtonStyle(primary: false))
            HStack(spacing: 16) {
              Button("Open settings") { Task { await model.action("permission") } }
              Button("Check again") { Task { await model.refresh() } }
            }.buttonStyle(.link).font(.caption)
            Text(
              "Already enabled? Turn Afterimage off and on in System Settings, then quit and reopen it."
            )
            .font(.caption).foregroundStyle(.secondary)
          }

        }
        if step == 2 {
          HStack(spacing: 18) {
            Label("Search  ⌘F", systemImage: "magnifyingglass")
            Label("Browse  ← →", systemImage: "clock")
          }.font(.caption).foregroundStyle(.secondary)
        }
      }.id(step).transition(.opacity)
      Spacer()
      HStack {
        if step > 0 {
          Button("Back") { advance(-1) }.buttonStyle(SetupButtonStyle(primary: false))
        }
        Spacer()
        Button(step == 2 ? (model.startingCapture ? "Starting…" : "Start recording") : "Continue") {
          if step == 2 { Task { await model.startFromOnboarding() } } else { advance(1) }
        }.buttonStyle(SetupButtonStyle())
          .disabled(model.startingCapture || (step > 0 && !model.state.permission))
          .keyboardShortcut(.defaultAction)

      }
    }.padding(40).padding(.top, 16).frame(width: 580, height: 570)
      .ignoresSafeArea(.container, edges: .top)
      .background(Color(nsColor: .windowBackgroundColor))
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        Task { await model.refresh() }
      }
  }

  private func advance(_ delta: Int) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step += delta }
  }
}
