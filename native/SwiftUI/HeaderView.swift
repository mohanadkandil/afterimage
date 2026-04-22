import SwiftUI

struct HeaderView: View {
  @Bindable var model: MemoryModel
  @FocusState.Binding var searchFocused: Bool
  var body: some View {
    HStack(spacing: 24) {
      HStack(spacing: 3) {
        ForEach(0..<3) { i in
          RoundedRectangle(cornerRadius: 2).fill(Style.mint.opacity([1, 0.65, 0.35][i])).frame(
            width: 5, height: [18, 25, 14][i]
          ).rotationEffect(.degrees(12))
        }
      }.frame(width: 26)
      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search something you saw", text: $model.query).textFieldStyle(.plain).focused(
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
      }.padding(.horizontal, 11).frame(height: 34).background(
        Style.faint, in: RoundedRectangle(cornerRadius: 8)
      ).frame(maxWidth: 440)
      Spacer(minLength: 0)
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
          .background(Style.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
      }.buttonStyle(.plain)
      IconButton(symbol: "slider.horizontal.3", title: "Settings") { model.showSettings = true }
    }

  }
}
