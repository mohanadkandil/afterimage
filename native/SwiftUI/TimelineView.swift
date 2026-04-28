import SwiftUI

struct TimelineView: View {
  @Bindable var model: MemoryModel

  private func color(_ bundle: String) -> Color {
    let hash = bundle.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
    return Color(hue: Double(hash % 360) / 360, saturation: 0.48, brightness: 0.8)
  }

  private func markers(_ spans: [TimelineSpan], start: Double, duration: Double, width: CGFloat)
    -> [TimelineSpan]
  {
    var previous: CGFloat = -32
    return spans.filter { span in
      let position = min(width - 20, CGFloat((span.first.time - start) / duration) * width)
      guard position - previous >= 32 else { return false }
      previous = position
      return true
    }
  }

  var body: some View {
    GeometryReader { geo in
      let spans = TimelineSpan.grouped(model.moments)
      let start = model.moments.first?.time ?? 0
      let duration = max(1, (spans.last?.end ?? start + 1) - start)
      let width = max(1, geo.size.width)
      ZStack(alignment: .topLeading) {
        ZStack(alignment: .leading) {
          Rectangle().fill(Style.faint)
          ForEach(spans) { span in
            let x = CGFloat((span.first.time - start) / duration) * width
            Rectangle().fill(color(span.first.bundle))
              .frame(width: max(1, CGFloat((span.end - span.first.time) / duration) * width))
              .offset(x: x)
              .help(span.first.app)
          }
        }.frame(width: width, height: 8).clipShape(Capsule()).offset(y: 28)

        ForEach(markers(spans, start: start, duration: duration, width: width)) { span in
          Button {
            model.select(span.first.id)
          } label: {
            AppLogo(model: model, bundle: span.first.bundle, size: 20)
          }.buttonStyle(.plain).help(span.first.app)
            .accessibilityLabel("Jump to \(span.first.app)")
            .offset(x: min(width - 20, CGFloat((span.first.time - start) / duration) * width))
        }

        if let current = model.current {
          Capsule().fill(.primary).frame(width: 3, height: 22)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .offset(x: min(width - 3, CGFloat((current.time - start) / duration) * width), y: 21)
            .allowsHitTesting(false)
        }
      }.frame(width: width, height: 48).contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0).onChanged { value in
            let time = start + max(0, min(1, value.location.x / width)) * duration
            if let nearest = model.moments.min(by: { abs($0.time - time) < abs($1.time - time) }) {
              model.select(nearest.id)
            }
          }
        )
        .background(HorizontalWheelSupport(move: { model.move($0) }))
    }.accessibilityElement(children: .contain).accessibilityLabel("Recorded moments timeline")
  }
}
