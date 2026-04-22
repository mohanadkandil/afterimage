import AppKit
import Observation
import SwiftUI

struct TimelineView: View {
  @Bindable var model: MemoryModel
  private var markers: [Moment] {
    model.moments.enumerated().compactMap { i, m in
      i == 0 || model.moments[i - 1].bundle != m.bundle ? m : nil
    }
  }
  var body: some View {
    GeometryReader { geo in
      let start = model.moments.first?.time ?? 0
      let duration = max(1, (model.moments.last?.time ?? start) - start)
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 3).fill(Style.faint).frame(height: 6).offset(y: 27)
        ForEach(Array(model.moments.enumerated()), id: \.element.id) { i, moment in
          let end =
            i + 1 < model.moments.count
            ? min(model.moments[i + 1].time, moment.time + 30) : moment.time + 1
          RoundedRectangle(cornerRadius: 3).fill(Style.mint.opacity(0.65)).frame(
            width: max(
              3,
              min(
                geo.size.width,
                min(
                  CGFloat((end - moment.time) / duration) * geo.size.width,
                  geo.size.width
                    - min(
                      geo.size.width - 3, CGFloat((moment.time - start) / duration) * geo.size.width
                    )))),
            height: 6
          ).offset(
            x: min(geo.size.width - 3, CGFloat((moment.time - start) / duration) * geo.size.width),
            y: 27)
        }
        ForEach(markers) { moment in
          Button {
            model.select(moment.id)
          } label: {
            AppLogo(model: model, bundle: moment.bundle, size: 19)
          }.buttonStyle(.plain).help(moment.app).accessibilityLabel("Jump to \(moment.app)")
            .offset(
              x: min(
                geo.size.width - 20, CGFloat((moment.time - start) / duration) * geo.size.width),
              y: 0)
        }
        if let current = model.current {
          Capsule().fill(Color.primary.opacity(0.85)).frame(width: 3, height: 16).offset(
            x: min(geo.size.width - 3, CGFloat((current.time - start) / duration) * geo.size.width),
            y: 22
          ).allowsHitTesting(false)
        }
      }.contentShape(Rectangle()).gesture(
        DragGesture(minimumDistance: 0).onChanged { model.seek($0.location.x / geo.size.width) })
    }.accessibilityElement(children: .contain).accessibilityLabel("Recorded moments timeline")
  }
}
