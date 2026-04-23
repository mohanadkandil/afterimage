import SwiftUI

struct PlaybackControls: View {
  @Bindable var model: MemoryModel
  var body: some View {
    HStack(spacing: 6) {
      IconButton(
        symbol: model.playing ? "pause.fill" : "play.fill", title: "Play or pause saved moments"
      ) { model.togglePlayback() }.disabled(model.moments.isEmpty)
      IconButton(symbol: "chevron.left", title: "Previous moment") { model.move(-1) }.disabled(
        model.index == 0)
      IconButton(symbol: "chevron.right", title: "Next moment") { model.move(1) }.disabled(
        model.index >= model.moments.count - 1)
      if let current = model.current {
        Text(current.date, format: .dateTime.hour().minute().second())
          .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if model.offset > 0 {
        Button("Newer") {
          model.offset = max(0, model.offset - 200)
          Task { await model.load() }
        }.buttonStyle(QuietButton())
      }
      if model.moments.count == 200 {
        Button("Earlier") {
          model.offset += 200
          Task { await model.load() }
        }.buttonStyle(QuietButton())
      }
      if !model.moments.isEmpty {
        Menu {
          ForEach([1.0, 2.0, 4.0], id: \.self) { speed in
            Button("\(Int(speed))×") { model.playbackSpeed = speed }
          }
        } label: {
          Text("\(Int(model.playbackSpeed))×").font(.system(size: 11)).foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
        IconButton(symbol: "minus.magnifyingglass", title: "Zoom out") {
          model.zoom = max(1, model.zoom - 0.25)
        }
        Button(model.zoom == 1 ? "Fit" : "\(Int(model.zoom*100))%") { model.zoom = 1 }.buttonStyle(
          QuietButton()
        ).foregroundStyle(.secondary).help("Fit screenshot")
        IconButton(symbol: "plus.magnifyingglass", title: "Zoom in") {
          model.zoom = min(4, model.zoom + 0.25)
        }
      }
    }

  }
}
