import AppKit
import Observation
import SwiftUI

@objc(AfterimageSwiftUI) @MainActor
public final class AfterimageSwiftUI: NSViewController, NSWindowDelegate {
  private let model: MemoryModel
  private var monitor: Any?
  @objc public init(bridge: AfterimageBridge, root: String) {
    model = MemoryModel(bridge: bridge, root: root)
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  public override func loadView() {
    view = NSHostingView(
      rootView: AfterimageRootView(
        model: model, setupChanged: { [weak self] setup in self?.configureWindow(setup) },
        settingsChanged: { [weak self] visible in self?.presentSettings(visible) }))
  }
  public override func viewDidAppear() {
    super.viewDidAppear()
    configureWindow(model.showOnboarding)
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window == self.view.window, !self.model.showSettings,
        !self.model.showOnboarding
      else {
        return event
      }
      if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "f" {
        NotificationCenter.default.post(name: .init("AfterimageFocusSearch"), object: nil)
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
          NotificationCenter.default.post(name: .init("AfterimageFocusSearch"), object: nil)
          return nil
        }
        return event
      }
    }
  }
  private var settingsWindow: NSWindow?
  private func presentSettings(_ visible: Bool) {
    if !visible {
      settingsWindow?.close()
      if model.replayIntroduction {
        model.replayIntroduction = false
        model.showOnboarding = true
      }
      return
    }
    if let settingsWindow {
      settingsWindow.makeKeyAndOrderFront(nil)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.title = "Settings"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(
      rootView: SettingsView(model: model, prefs: model.state.settings))
    window.center()
    settingsWindow = window
    window.makeKeyAndOrderFront(nil)
  }
  public func windowWillClose(_ notification: Notification) {
    guard let closed = notification.object as? NSWindow, closed === settingsWindow else { return }
    settingsWindow = nil
    model.showSettings = false
  }
  private var browsingSize = NSSize(width: 1380, height: 900)
  private func configureWindow(_ setup: Bool) {
    guard let window = view.window else { return }
    if setup {
      if window.contentLayoutRect.width > 700 { browsingSize = window.contentLayoutRect.size }
      window.minSize = NSSize(width: 580, height: 570)
      window.styleMask.remove(.resizable)
      window.setContentSize(NSSize(width: 580, height: 570))
    } else {
      window.styleMask.insert(.resizable)
      window.minSize = NSSize(width: 840, height: 600)
      window.setContentSize(browsingSize)
    }
    window.center()
  }
  @objc public func refresh() { Task { await model.refresh() } }
  @objc public func showSettings(_ sender: Any?) {
    if !model.showOnboarding { model.showSettings = true }
  }
  @objc public func smoke(_ output: String) {
    Task {
      try? await Task.sleep(for: .milliseconds(450))
      if let introView = Optional(view),
        let rep = introView.bitmapImageRepForCachingDisplay(in: introView.bounds)
      {
        introView.cacheDisplay(in: introView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: output + "-onboarding.png"))
      }
      let introductionWasShown = model.showOnboarding
      model.finishOnboarding()
      let setupWasGated = model.showOnboarding
      model.showOnboarding = false
      try? await Task.sleep(for: .milliseconds(350))
      await model.refresh()
      await model.load()
      var checks: [String: Bool] = [
        "permissionGatesCompletion": setupWasGated,
        "firstLaunchIntroduction": introductionWasShown,
        "swiftUIHost": view is NSHostingView<AfterimageRootView>,
        "nativeWindow": view.window != nil,
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
        try? await Task.sleep(for: .milliseconds(150))
        @MainActor func wheel(in node: NSView) -> HorizontalWheelSupport.WheelRegion? {
          if let region = node as? HorizontalWheelSupport.WheelRegion { return region }
          for child in node.subviews { if let found = wheel(in: child) { return found } }
          return nil
        }
        if model.moments.count > 1, let region = wheel(in: view) {
          model.seek(0)
          region.consume(deltaX: 0, deltaY: -1, precise: false, timestamp: 1)
          checks["mouseWheelNextFrame"] = model.index == 1
          region.consume(deltaX: 0, deltaY: 1, precise: false, timestamp: 2)
          checks["mouseWheelPreviousFrame"] = model.index == 0
          region.consume(deltaX: -12, deltaY: 0, precise: true, timestamp: 3)
          checks["trackpadAccumulates"] = model.index == 0
          region.consume(deltaX: -12, deltaY: 0, precise: true, timestamp: 3.1)
          checks["trackpadNextFrame"] = model.index == 1
        } else {
          checks["timelineWheelMounted"] = false
        }

      } else {
        checks["empty"] = model.current == nil
      }
      model.showSettings = true
      try? await Task.sleep(for: .milliseconds(400))
      checks["settings"] = settingsWindow?.isVisible == true
      if let settingsView = settingsWindow?.contentView,
        let rep = settingsView.bitmapImageRepForCachingDisplay(in: settingsView.bounds)
      {
        settingsView.cacheDisplay(in: settingsView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: output + "-settings.png"))
      }
      settingsWindow?.contentView = NSHostingView(
        rootView: SettingsView(model: model, prefs: model.state.settings, tab: "Storage"))
      try? await Task.sleep(for: .milliseconds(350))
      if let storage = settingsWindow?.contentView,
        let rep = storage.bitmapImageRepForCachingDisplay(in: storage.bounds)
      {
        storage.cacheDisplay(in: storage.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: output + "-storage.png"))
      }
      checks["storageByteCounts"] =
        model.state.diskBytes >= model.state.imageBytes && model.state.diskBytes > 0
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
