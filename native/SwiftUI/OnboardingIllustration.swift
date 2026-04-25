import SwiftUI

/// An abstract illustration of the workflow, not fabricated archive content.
struct OnboardingIllustration: View {
  let step: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 18)
        .fill(Style.mint.opacity(0.045))
      if step == 1 {
        HStack(spacing: 22) {
          Image(systemName: "macwindow").font(.system(size: 36, weight: .ultraLight))
            .foregroundStyle(.secondary)
          Rectangle().fill(Style.mint.opacity(0.3)).frame(width: 42, height: 1)
          Image(systemName: "lock.shield").font(.system(size: 40, weight: .ultraLight))
            .foregroundStyle(Style.mint)
        }
      } else {
        VStack(spacing: 20) {
          HStack(spacing: 10) {
            Image(systemName: step == 0 ? "clock.arrow.circlepath" : "magnifyingglass")
              .foregroundStyle(Style.mint)
            Text(step == 0 ? "A moment worth keeping" : "A word brings it back")
              .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
          }
          ZStack(alignment: .leading) {
            Capsule().fill(.secondary.opacity(0.15)).frame(height: 2)
            HStack {
              ForEach(0..<5) { index in
                Circle().fill(index == 3 ? Style.mint : Color.secondary.opacity(0.4))
                  .frame(width: index == 3 ? 9 : 5, height: index == 3 ? 9 : 5)
                  .overlay {
                    if index == 3 {
                      Circle().strokeBorder(Style.mint.opacity(0.25), lineWidth: 1)
                        .frame(width: 23, height: 23)
                    }
                  }
                if index != 4 { Spacer() }
              }
            }
          }.frame(width: 260)
        }
      }
    }.frame(height: 118)
      .opacity(revealed ? 1 : 0)
      .offset(y: revealed || reduceMotion ? 0 : 5)
      .onAppear {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { revealed = true }
      }
      .accessibilityHidden(true)
  }
}
