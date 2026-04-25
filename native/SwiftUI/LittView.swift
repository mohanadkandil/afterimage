import AppKit
import Observation
import SwiftUI

struct LittView: View {
  @Bindable var model: MemoryModel
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showFilmstrip = false
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    VStack(spacing: 0) {
      HeaderView(model: model, searchFocused: $searchFocused)
        .padding(.leading, 84).padding(.trailing, 18).frame(height: 52)
      ScreenshotView(model: model)
      if showFilmstrip && model.current != nil {
        FilmstripView(model: model).padding(.top, 10)
          .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
      HStack(spacing: 8) {
        Button {
          model.showDate.toggle()
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "calendar")
            Text(model.day, format: .dateTime.day().month(.abbreviated))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
          }
        }.buttonStyle(QuietButton()).popover(isPresented: $model.showDate) {
          VStack {
            DatePicker("Recording date", selection: $model.day, displayedComponents: .date)
              .datePickerStyle(.graphical).labelsHidden()
            Button("Today") {
              model.day = Date()
              model.showDate = false
            }
            .buttonStyle(QuietButton())
          }.padding(16).frame(width: 290)
        }
        PlaybackControls(model: model)
        IconButton(
          symbol: "rectangle.stack", title: showFilmstrip ? "Hide thumbnails" : "Show thumbnails"
        ) {
          withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.08)) {
            showFilmstrip.toggle()
          }
        }.disabled(model.current == nil)
        IconButton(symbol: "text.alignleft", title: "Text and details") {
          model.showDetails.toggle()
        }.disabled(model.current == nil)
          .popover(isPresented: $model.showDetails) { EvidenceView(model: model) }
        Menu {
          Button("Import screenshots…") { Task { await model.importImages() } }
            .disabled(model.importing)
          Button("Export screenshot…") { Task { await model.exportImage() } }
            .disabled(model.current == nil)
        } label: {
          Image(systemName: "ellipsis").frame(width: 24, height: 30)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .help("Import and export").accessibilityLabel("Import and export")
      }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
      if !model.moments.isEmpty {
        TimelineView(model: model).frame(height: 44).padding(.horizontal, 22).padding(.bottom, 8)
      }
    }
    .ignoresSafeArea(.container, edges: .top)
    .background(
      colorScheme == .dark
        ? Color(red: 0.075, green: 0.087, blue: 0.09) : Color(red: 0.97, green: 0.974, blue: 0.97)
    )
    .tint(Style.mint)
    .sheet(isPresented: $model.showOnboarding) {
      OnboardingView(model: model).interactiveDismissDisabled()
    }
    .sheet(
      isPresented: $model.showSettings,
      onDismiss: {
        if model.replayIntroduction {
          model.replayIntroduction = false
          model.showOnboarding = true
        }
      }
    ) {
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
