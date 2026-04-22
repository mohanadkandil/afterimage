import AppKit
import Observation
import SwiftUI

struct EvidenceView: View {
  @Bindable var model: MemoryModel
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let current = model.current {
        HStack(spacing: 10) {
          AppLogo(model: model, bundle: current.bundle, size: 28)
          VStack(alignment: .leading, spacing: 3) {
            Text(current.app).font(.headline)
            Text(current.date.formatted(date: .abbreviated, time: .standard)).font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        ScrollView {
          Text(current.text.isEmpty ? "No text recognized in this frame." : current.text).font(
            .system(size: 13)
          ).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 280)
        Text("Text recognized on this Mac. The screenshot is the original evidence.").font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          Button("Delete…", role: .destructive) {
            model.showDetails = false
            model.confirmDelete = true
          }
          Spacer()
          Button("Copy text") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(current.text, forType: .string)
          }
        }
      }
    }.padding(22).frame(width: 360)
  }
}
