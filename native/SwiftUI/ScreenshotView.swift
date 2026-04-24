import AppKit
import Observation
import SwiftUI

struct ScreenshotView: View {
  @Bindable var model: MemoryModel
  var body: some View {
    GeometryReader { geo in
      ZStack {
        Color.primary.opacity(0.035)
        if let current = model.current, let image = model.image(current) {
          let ratio = min(
            geo.size.width / CGFloat(current.width), geo.size.height / CGFloat(current.height))
          let width = CGFloat(current.width) * ratio * model.zoom
          let height = CGFloat(current.height) * ratio * model.zoom
          ScrollView([.horizontal, .vertical], showsIndicators: model.zoom > 1) {
            Image(nsImage: image).resizable().interpolation(.high).frame(
              width: width, height: height
            )
            .overlay(alignment: .topLeading) {
              ForEach(Array(current.boxes.enumerated()), id: \.offset) { _, box in
                if model.matches(box) {
                  RoundedRectangle(cornerRadius: 2).fill(Style.mint.opacity(0.2)).overlay(
                    RoundedRectangle(cornerRadius: 2).strokeBorder(
                      Style.mint.opacity(0.8), lineWidth: 1)
                  ).frame(width: box.w * width, height: box.h * height).offset(
                    x: box.x * width, y: box.y * height)
                }
              }
            }.frame(minWidth: geo.size.width, minHeight: geo.size.height)
          }
          VStack {
            HStack {
              HStack(spacing: 8) {
                AppLogo(model: model, bundle: current.bundle, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                  Text(current.app).font(.system(size: 11, weight: .medium))
                  Text(
                    current.source == "import"
                      ? "Imported screenshot"
                      : current.date.formatted(date: .omitted, time: .standard)
                  ).font(.system(size: 9)).foregroundStyle(.secondary)
                }
              }.padding(.horizontal, 10).padding(.vertical, 8).modifier(GlassSurface()).help(
                "Source application: \(current.app)")
              Spacer()
            }
            Spacer()
          }.padding(14).allowsHitTesting(false)
        } else {
          VStack(spacing: 14) {
            Image(systemName: model.query.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
              .font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
            Text(model.query.isEmpty ? "A place to return to." : "No matching moments.").font(
              .system(size: 24, weight: .medium)
            ).tracking(-0.6)
            Text(
              model.query.isEmpty
                ? "Your screen, saved for later." : "Try another phrase, date, or app."
            ).font(.system(size: 12)).foregroundStyle(.secondary)
            if model.query.isEmpty {
              Button("Import a screenshot") { Task { await model.importImages() } }.buttonStyle(
                QuietButton()
              ).padding(.top, 4)
            }
          }
        }
      }.clipped()
    }.frame(minHeight: 140)
  }
}
