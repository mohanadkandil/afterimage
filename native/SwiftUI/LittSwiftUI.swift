import AppKit
import Observation
import SwiftUI

@objc(LittSwiftUI) @MainActor public final class LittSwiftUI: NSViewController {
  private let model: MemoryModel
  private var monitor: Any?
  @objc public init(bridge: LittBridge, root: String) {
    model = MemoryModel(bridge: bridge, root: root)
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  public override func loadView() { view = NSHostingView(rootView: LittView(model: model)) }
  public override func viewDidAppear() {
    super.viewDidAppear()
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window == self.view.window, !self.model.showSettings else {
        return event
      }
      if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "f" {
        NotificationCenter.default.post(name: .init("LittFocusSearch"), object: nil)
        return nil
      }
      if self.view.window?.firstResponder is NSTextView { return event }
      switch event.keyCode {
      case 123:
        self.model.move(-1)
        return nil
      case 124:
        self.model.move(1)
        return nil
      case 49:
        self.model.togglePlayback()
        return nil
      case 53:
        self.model.showDetails = false
        self.model.showDate = false
        return nil
      default:
        if event.characters == "/" {
          NotificationCenter.default.post(name: .init("LittFocusSearch"), object: nil)
          return nil
        }
        return event
      }
    }
  }
  @objc public func refresh() { Task { await model.refresh() } }
  @objc public func showSettings(_ sender: Any?) { model.showSettings = true }
  @objc public func smoke(_ output: String) {
    Task {
      try? await Task.sleep(for: .milliseconds(450))
      if let introView = view.window?.sheets.first?.contentView,
        let rep = introView.bitmapImageRepForCachingDisplay(in: introView.bounds)
      {
        introView.cacheDisplay(in: introView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: output + "-onboarding.png"))
      }
      let introductionWasShown = model.showOnboarding
      model.finishOnboarding()
      try? await Task.sleep(for: .milliseconds(350))
      await model.refresh()
      await model.load()
      var checks: [String: Bool] = [
        "onboardingCompletion": !model.showOnboarding
          && FileManager.default.fileExists(
            atPath: model.root.appendingPathComponent(".onboarding-complete").path),
        "firstLaunchIntroduction": introductionWasShown,
        "swiftUIHost": view is NSHostingView<LittView>, "nativeWindow": view.window != nil,
      ]
      if !model.moments.isEmpty {
        checks["imageLoaded"] = model.current.flatMap { model.image($0) } != nil
        model.query = "seahorse742"
        await model.filter()
        checks["search"] = !model.moments.isEmpty
        checks["ocrHighlights"] = model.current?.boxes.contains(where: model.matches) ?? false
        model.query = "no-real-token-888734"
        await model.filter()
        checks["searchMiss"] = model.moments.isEmpty
        model.query = "seahorse742"
        await model.filter()
        if let bundle = model.state.apps.first?.bundle {
          model.app = bundle
          await model.filter()
          checks["appFilter"] = !model.moments.isEmpty
          model.app = ""
        }
        let saved = model.day
        model.day = saved.addingTimeInterval(-86400 * 3)
        await model.filter()
        checks["dateFilter"] = model.moments.isEmpty
        model.day = saved
        await model.filter()
        model.seek(0)
        checks["scrub"] = model.selected == model.moments.first?.id
        if model.moments.count > 1 {
          model.move(1)
          checks["navigation"] = model.index == 1
        }
        model.zoom = 1.5
        checks["zoom"] = model.zoom == 1.5
        model.zoom = 1
        checks["realAppIcon"] = model.appIcon("com.apple.finder") != nil
        checks["unknownIconFallback"] = model.appIcon("not.an.installed.app.9345") == nil
      } else {
        checks["empty"] = model.current == nil
      }
      if let bridge = model.bridge {
        let reopened = MemoryModel(bridge: bridge, root: model.root.path)
        checks["onboardingPersists"] = !reopened.showOnboarding
      }
      model.showSettings = true
      try? await Task.sleep(for: .milliseconds(400))
      checks["settings"] = !(view.window?.sheets.isEmpty ?? true)
      if let settingsView = view.window?.sheets.first?.contentView,
        let rep = settingsView.bitmapImageRepForCachingDisplay(in: settingsView.bounds)
      {
        settingsView.cacheDisplay(in: settingsView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: output + "-settings.png"))
      }
      model.showSettings = false
      try? await Task.sleep(for: .milliseconds(500))
      view.layoutSubtreeIfNeeded()
      let result: [String: Any] = ["passed": checks.values.allSatisfy { $0 }, "checks": checks]
      try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(
        to: URL(fileURLWithPath: output + ".json"))
      if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: output + ".png"))
      }
      exit(checks.values.allSatisfy { $0 } ? 0 : 3)
    }
  }
}
