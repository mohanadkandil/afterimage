import AppKit
import SwiftUI

struct TimelineView: View {
  @Bindable var model: MemoryModel
  private func color(_ bundle: String) -> Color {
    let hash = bundle.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
    return Color(hue: Double(hash % 360) / 360, saturation: 0.48, brightness: 0.8)
  }
  var body: some View {
    GeometryReader { geo in
      let start = model.moments.first?.time ?? 0
      let duration = max(1, (model.moments.last?.time ?? start) - start)
      let width = max(geo.size.width, min(16000, duration * 3))
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          ZStack(alignment: .topLeading) {
            Capsule().fill(Style.faint).frame(width: width, height: 8).offset(y: 27)
            ForEach(Array(model.moments.enumerated()), id: \.element.id) { i, moment in
              let x = min(width - 4, (moment.time - start) / duration * width)
              let end =
                i + 1 < model.moments.count
                ? min(model.moments[i + 1].time, moment.time + 30) : moment.time + 1
              Capsule().fill(color(moment.bundle))
                .frame(
                  width: max(4, min(width - x, (end - moment.time) / duration * width)), height: 8
                )
                .offset(x: x, y: 27).help(moment.app).id(moment.id)
              if i == 0 || model.moments[i - 1].bundle != moment.bundle {
                Button {
                  model.select(moment.id)
                } label: {
                  AppLogo(model: model, bundle: moment.bundle, size: 19)
                }.buttonStyle(.plain).help(moment.app).accessibilityLabel("Jump to \(moment.app)")
                  .offset(x: min(width - 20, x), y: 0)
              }
            }
            if let current = model.current {
              Capsule().fill(.primary).frame(width: 3, height: 18)
                .offset(x: min(width - 3, (current.time - start) / duration * width), y: 22)
                .allowsHitTesting(false)
            }
          }.frame(width: width, height: 42).contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 0).onChanged { model.seek($0.location.x / width) })
        }.background(HorizontalWheelSupport(move: { model.move($0) }))
          .onChange(of: model.selected) { _, id in
            if let id { proxy.scrollTo(id, anchor: .center) }
          }
      }
    }.accessibilityElement(children: .contain).accessibilityLabel("Recorded moments timeline")
  }
}
