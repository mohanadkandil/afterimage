import SwiftUI

struct HeaderView: View {
  @Bindable var model: MemoryModel
  @FocusState.Binding var searchFocused: Bool
  var body: some View {
    HStack(spacing: 16) {
      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search your moments", text: $model.query).textFieldStyle(.plain).focused(
          $searchFocused
        ).font(.system(size: 13))
        if !model.query.isEmpty {
          Button {
            model.query = ""
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }.buttonStyle(.plain).help("Clear search")
        } else {
          Text("⌘ F").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
      }.frame(height: 34).frame(maxWidth: 360)
      Spacer(minLength: 16)
      Menu {
        Button("All applications") { model.app = "" }
        ForEach(model.state.apps) { app in Button(app.name) { model.app = app.bundle } }
      } label: {
        Text(model.state.apps.first(where: { $0.bundle == model.app })?.name ?? "All apps")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }.menuStyle(.borderlessButton).fixedSize()
      HStack(spacing: 6) {
        Circle().fill(model.state.recording ? Style.mint : Color.secondary.opacity(0.5)).frame(
          width: 5, height: 5)
        Text(model.importing ? "Importing…" : model.state.captureState).lineLimit(1)
      }.font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: 160).help(
        model.state.error)
      Button {
        Task { await model.toggleRecording() }
      } label: {
        Label(
          model.state.recording ? "Pause" : "Record",
          systemImage: model.state.recording ? "pause.fill" : "record.circle"
        ).font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 32)
          .modifier(GlassSurface(interactive: true, accented: true))
      }.buttonStyle(.plain)
      IconButton(symbol: "gearshape", title: "Settings") { model.showSettings = true }
    }

  }
}
