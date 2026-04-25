import AppKit
import Observation
import SwiftUI

struct SettingsView: View {
  @Bindable var model: MemoryModel
  @State var prefs: Preferences
  @State private var extra = ""
  @State private var tab = "Capture"
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Settings").font(.system(size: 20, weight: .semibold))
        Spacer()
        IconButton(symbol: "xmark", title: "Close settings") { model.showSettings = false }
      }.padding(24)
      Picker("Settings section", selection: $tab) {
        Text("Capture").tag("Capture")
        Text("Privacy").tag("Privacy")
        Text("Storage").tag("Storage")
      }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 12)
      Form {
        if tab == "Capture" {
          Section("Capture") {
            Picker("Sample every", selection: $prefs.interval) {
              ForEach([1, 2, 5, 10, 30], id: \.self) { Text("\($0) seconds").tag($0) }
            }

            Text("Similar frames are skipped. Recording starts only when you choose.").font(
              .caption
            )
            .foregroundStyle(.secondary)
          }
          Section("Getting started") {
            LabeledContent(
              "Screen Recording", value: model.state.permission ? "Allowed" : "Not allowed")
            Button("Screen Recording permission…") { Task { await model.action("permission") } }
            Button("Replay introduction") {
              model.replayIntroduction = true
              model.showSettings = false
            }
          }
        }
        if tab == "Privacy" {
          Section("Excluded apps") {
            ForEach(model.state.runningApps) { app in
              Toggle(
                isOn: Binding(
                  get: { prefs.excluded.contains(app.bundle) },
                  set: {
                    if $0 {
                      if !prefs.excluded.contains(app.bundle) { prefs.excluded.append(app.bundle) }
                    } else {
                      prefs.excluded.removeAll { $0 == app.bundle }
                    }
                  })
              ) {
                HStack {
                  AppLogo(model: model, bundle: app.bundle, size: 20)
                  Text(app.name)
                }
              }
            }
            TextField("Additional bundle IDs", text: $extra, prompt: Text("com.example.private"))
            Text("Recording waits while an excluded app is focused.").font(.caption)
              .foregroundStyle(
                .secondary)
          }
        }
        if tab == "Storage" {
          Section("On this Mac") {
            Picker("Keep history", selection: $prefs.retentionDays) {
              ForEach([1, 7, 14, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) }
            }
            LabeledContent("Saved moments", value: "\(model.state.count)")
            Text("Older moments are removed automatically. Your archive stays on this Mac.").font(
              .caption
            ).foregroundStyle(.secondary)
            Button("Show archive in Finder") { Task { await model.action("reveal") } }
            Button("Delete all history…", role: .destructive) {
              model.showSettings = false
              model.confirmClear = true
            }
          }
        }
      }.formStyle(.grouped)
      HStack {
        Text("Local storage · No account").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { model.showSettings = false }.buttonStyle(QuietButton()).keyboardShortcut(
          .cancelAction)
        Button("Save") {
          let known = Set(model.state.runningApps.map(\.bundle))
          prefs.excluded =
            prefs.excluded.filter { known.contains($0) }
            + extra.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
          Task { await model.save(prefs) }
        }.buttonStyle(QuietButton()).modifier(GlassSurface(interactive: true)).keyboardShortcut(
          .defaultAction)
      }.padding(20)
    }.frame(width: 520, height: 570).background(Color(nsColor: .windowBackgroundColor)).onAppear {
      let known = Set(model.state.runningApps.map(\.bundle))
      extra = prefs.excluded.filter { !known.contains($0) }.joined(separator: ", ")
    }
  }
}
