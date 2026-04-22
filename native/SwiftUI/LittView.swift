import AppKit
import Observation
import SwiftUI

struct LittView: View {
  @Bindable var model: MemoryModel
  @FocusState private var searchFocused: Bool
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    VStack(spacing: 0) {
      HeaderView(model: model, searchFocused: $searchFocused).padding(.horizontal, 22).padding(
        .top, 12
      ).padding(.bottom, 14)
      HStack(spacing: 8) {
        Button {
          model.showDate.toggle()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "calendar")
            Text(model.day, format: .dateTime.day().month(.abbreviated).year())
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
          }
        }.buttonStyle(QuietButton()).popover(isPresented: $model.showDate) {
          DatePicker("Recording date", selection: $model.day, displayedComponents: .date)
            .datePickerStyle(.graphical).labelsHidden().padding(16).frame(width: 290)
        }
        if !Calendar.current.isDateInToday(model.day) {
          Button("Today") { model.day = Date() }.buttonStyle(QuietButton()).foregroundStyle(
            .secondary)
        }
        Spacer()
        Menu {
          Button("All applications") { model.app = "" }
          ForEach(model.state.apps) { app in Button(app.name) { model.app = app.bundle } }
        } label: {
          HStack(spacing: 6) {
            Text(model.state.apps.first(where: { $0.bundle == model.app })?.name ?? "All apps")
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
          }.font(.system(size: 12)).foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.primary).fixedSize()
        IconButton(symbol: "square.and.arrow.down", title: "Import screenshots") {
          Task { await model.importImages() }
        }.disabled(model.importing)
        IconButton(symbol: "text.alignleft", title: "Text and details") {
          model.showDetails.toggle()
        }.disabled(model.current == nil)
          .popover(isPresented: $model.showDetails) { EvidenceView(model: model) }
        IconButton(symbol: "square.and.arrow.up", title: "Export screenshot") {
          Task { await model.exportImage() }
        }.disabled(model.current == nil)
      }.padding(.horizontal, 18).padding(.bottom, 10)
      ScreenshotView(model: model).padding(.horizontal, 20)
      if let current = model.current {
        HStack {
          Text(current.title.isEmpty ? current.app : current.title).lineLimit(1)
          Spacer()
          Text("\(current.width) × \(current.height)").monospacedDigit()
        }
        .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(
          .vertical, 9)
        FilmstripView(model: model)
      }
      PlaybackControls(model: model).padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
      if !model.moments.isEmpty {
        TimelineView(model: model).frame(height: 44).padding(.horizontal, 26).padding(.bottom, 12)
      }
    }
    .background(
      colorScheme == .dark
        ? Color(red: 0.075, green: 0.087, blue: 0.09) : Color(red: 0.97, green: 0.974, blue: 0.97)
    )
    .tint(Style.mint)
    .sheet(isPresented: $model.showSettings) {
      SettingsView(model: model, prefs: model.state.settings)
    }
    .alert(
      "Litt",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      if model.state.captureState == "Permission needed" {
        Button("Open System Settings") { Task { await model.action("permission") } }
      }
      Button("OK", role: .cancel) { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .confirmationDialog(
      "Delete this moment?", isPresented: $model.confirmDelete, titleVisibility: .visible
    ) {
      Button("Delete screenshot and text", role: .destructive) {
        Task { await model.deleteMoment() }
      }
    }
    .confirmationDialog(
      "Delete all history?", isPresented: $model.confirmClear, titleVisibility: .visible
    ) {
      Button("Delete all screenshots and text", role: .destructive) { Task { await model.clear() } }
    }
    .task { model.start() }
    .task(id: model.query) {
      do {
        try await Task.sleep(for: .milliseconds(200))
        await model.filter()
      } catch {}
    }
    .onChange(of: model.day) { _, _ in Task { await model.filter() } }
    .onChange(of: model.app) { _, _ in Task { await model.filter() } }
    .onReceive(NotificationCenter.default.publisher(for: .init("LittFocusSearch"))) { _ in
      searchFocused = true
    }
  }

}
