import AppKit
import SwiftUI

struct SettingsView: View {
  @Bindable var model: MemoryModel
  @State var prefs: Preferences
  @State private var extra = ""
  @State var tab = "Capture"
  @State private var saving = false
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Settings").font(.system(size: 17, weight: .semibold)).padding(.bottom, 22)
        navigation("Capture", symbol: "record.circle")
        navigation("Privacy", symbol: "hand.raised")
        navigation("Storage", symbol: "externaldrive")
        Spacer()
        Label("Only on this Mac", systemImage: "lock")
          .font(.system(size: 10)).foregroundStyle(.secondary)
      }.padding(18).padding(.top, 36).frame(width: 190)
        .frame(maxHeight: .infinity).background(.ultraThinMaterial)
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(tab).font(.system(size: 23, weight: .semibold)).tracking(-0.4)
          Spacer()
          if saving { ProgressView().controlSize(.small).accessibilityLabel("Saving settings") }
        }.padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 24)
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if tab == "Capture" {
              group {
                HStack {
                  description("Screen capture", detail: model.state.captureState)
                  Spacer()
                  Toggle(
                    "Screen capture",
                    isOn: Binding(
                      get: { model.state.recording },
                      set: { _ in
                        Task { await model.toggleRecording() }
                      })
                  ).labelsHidden().toggleStyle(.switch).fixedSize()
                }
                Divider().opacity(0.35)
                HStack {
                  description("Sampling", detail: "Similar frames are skipped.")
                  Spacer()
                  Menu {
                    ForEach([1, 2, 5, 10, 30], id: \.self) { value in
                      Button("Every \(value) seconds") { prefs.interval = value }
                    }
                  } label: {
                    Text("Every \(prefs.interval)s")
                  }
                  .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Sample every")
                }
              }
              group {
                HStack {
                  description("Storage quality", detail: "Applies to new recordings.")
                  Spacer()
                  Menu {
                    Button("Balanced · HEVC") { prefs.compressionMode = "balanced" }
                    Button("Sharper · HEVC") { prefs.compressionMode = "sharp" }
                    Button("Keep JPEG images") { prefs.compressionMode = "jpeg" }
                  } label: {
                    Text(
                      prefs.compressionMode == "sharp"
                        ? "Sharper" : prefs.compressionMode == "jpeg" ? "JPEG images" : "Balanced")
                  }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Storage quality")
                }
              }
              group {
                HStack {
                  description(
                    "Screen permission",
                    detail: model.state.permission ? "Ready to capture" : "Access required")
                  Spacer()
                  Button("Manage…") { Task { await model.action("permission") } }.buttonStyle(
                    QuietButton())
                }
                Divider().opacity(0.35)
                HStack {
                  description("Introduction", detail: "Walk through setup again.")
                  Spacer()
                  Button("Open") {
                    model.replayIntroduction = true
                    model.showSettings = false
                  }
                  .buttonStyle(QuietButton())
                }
              }
            } else if tab == "Privacy" {
              Text("Capture pauses while an excluded app is in focus.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
              group {
                ForEach(model.state.runningApps) { app in
                  HStack(spacing: 10) {
                    AppLogo(model: model, bundle: app.bundle, size: 24)
                    Text(app.name).font(.system(size: 13))
                    Spacer()
                    Toggle(
                      "Exclude \(app.name)",
                      isOn: Binding(
                        get: { prefs.excluded.contains(app.bundle) },
                        set: { value in
                          prefs.excluded.removeAll { $0 == app.bundle }
                          if value { prefs.excluded.append(app.bundle) }
                        })
                    ).labelsHidden().toggleStyle(.switch).fixedSize()
                  }.padding(.vertical, 3)
                }
                if model.state.runningApps.isEmpty {
                  Text("Open an app to add it here.").foregroundStyle(.secondary)
                }
              }
              DisclosureGroup("Other excluded apps") {
                VStack(alignment: .leading, spacing: 8) {
                  ForEach(
                    prefs.excluded.filter { id in
                      !model.state.runningApps.contains { $0.bundle == id }
                    }, id: \.self
                  ) { id in
                    HStack {
                      Text(id).font(.caption)
                      Spacer()
                      Button("Remove") { prefs.excluded.removeAll { $0 == id } }.buttonStyle(
                        .borderless)
                    }
                  }
                  TextField("App bundle ID", text: $extra).textFieldStyle(.roundedBorder).onSubmit {
                    let value = extra.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty && !prefs.excluded.contains(value) {
                      prefs.excluded.append(value)
                    }
                    extra = ""
                  }
                }.padding(.top, 10)
              }.font(.system(size: 12))
            } else {
              VStack(alignment: .leading, spacing: 7) {
                Text(bytes(model.state.diskBytes)).font(.system(size: 38, weight: .medium))
                  .tracking(-1.2)
                Text("Total stored · \(model.state.count) moments").font(.system(size: 12))
                  .foregroundStyle(.secondary)
              }.padding(.bottom, 10)
              group {
                HStack {
                  Text("Recordings")
                  Spacer()
                  Text(bytes(model.state.imageBytes)).foregroundStyle(.secondary)
                }
                Divider().opacity(0.35)
                HStack {
                  Text("Preview cache")
                  Spacer()
                  Text(bytes(model.state.cacheBytes)).foregroundStyle(.secondary)
                }
                Divider().opacity(0.35)
                if model.state.workingBytes > 0 {
                  HStack {
                    Text("Temporary files")
                    Spacer()
                    Text(bytes(model.state.workingBytes)).foregroundStyle(.secondary)
                  }
                  Divider().opacity(0.35)
                }
                HStack {
                  Text("Text & database")
                  Spacer()
                  Text(
                    bytes(
                      max(
                        0, model.state.diskBytes - model.state.imageBytes - model.state.cacheBytes - model.state.workingBytes))
                  )
                  .foregroundStyle(.secondary)
                }
                Divider().opacity(0.35)
                HStack {
                  description("Keep history", detail: "Older moments are removed automatically.")
                  Spacer()
                  Menu {
                    ForEach([1, 7, 14, 30, 90, 365], id: \.self) { value in
                      Button("\(value) days") { prefs.retentionDays = value }
                    }
                  } label: {
                    Text("\(prefs.retentionDays) days")
                  }
                  .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Keep history")
                }
              }
              HStack {
                Button("Show in Finder") { Task { await model.action("reveal") } }.buttonStyle(
                  QuietButton())
                Spacer()
                Button("Delete history…", role: .destructive) {
                  model.showSettings = false
                  model.confirmClear = true
                }.buttonStyle(.borderless)
              }
            }
            if let error = model.error {
              Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
          }.padding(.horizontal, 28).padding(.bottom, 24)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          scheme == .dark
            ? Color(red: 0.095, green: 0.10, blue: 0.105) : Color(nsColor: .windowBackgroundColor))
    }.frame(width: 760, height: 560).ignoresSafeArea(.container, edges: .top).tint(Style.mint)
      .onDisappear { Task { await model.save(prefs, close: false) } }
      .task(id: prefs) {
        do {
          try await Task.sleep(for: .milliseconds(250))
          saving = true
          await model.save(prefs, close: false)
          saving = false
        } catch {}
      }
  }

  private func navigation(_ title: String, symbol: String) -> some View {
    Button {
      tab = title
    } label: {
      Label(title, systemImage: symbol).font(
        .system(size: 13, weight: tab == title ? .semibold : .regular)
      )
      .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 38)
      .modifier(SettingsSelection(selected: tab == title))
    }.buttonStyle(.plain).accessibilityAddTraits(tab == title ? .isSelected : [])
  }
  private func description(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 13, weight: .medium))
      Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }
  }
  private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 16, content: content).font(.system(size: 12))
      .padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }
  private func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }
}
