import AppKit
import Observation
import SwiftUI

@Observable @MainActor final class MemoryModel {
  @ObservationIgnored weak var bridge: LittBridge?
  let root: URL
  var state = ArchiveState()
  var moments: [Moment] = []
  var selected: Int64?
  var query = ""
  var day = Date()
  var app = ""
  var offset = 0
  var zoom: CGFloat = 1
  var showSettings = false
  var showOnboarding = false
  var replayIntroduction = false
  var showDetails = false
  var showDate = false
  var error: String?
  var importing = false
  var playing = false
  var playbackSpeed = 1.0
  var confirmDelete = false
  var confirmClear = false
  @ObservationIgnored private var poll: Task<Void, Never>?
  @ObservationIgnored private var playback: Task<Void, Never>?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var signature = ""
  @ObservationIgnored private var initialized = false
  @ObservationIgnored private var missingIcons: Set<String> = []
  @ObservationIgnored private var icons: [String: NSImage] = [:]
  @ObservationIgnored private let images = NSCache<NSNumber, NSImage>()
  var current: Moment? { moments.first { $0.id == selected } }
  var index: Int { moments.firstIndex { $0.id == selected } ?? 0 }
  init(bridge: LittBridge, root: String) {
    self.bridge = bridge
    self.root = URL(fileURLWithPath: root)
    images.countLimit = 16
    showOnboarding = !FileManager.default.fileExists(
      atPath: self.root.appendingPathComponent(".onboarding-complete").path)
  }
  func finishOnboarding() {
    do {
      try Data("1".utf8).write(
        to: root.appendingPathComponent(".onboarding-complete"), options: .atomic)
      showOnboarding = false
    } catch { self.error = error.localizedDescription }
  }
  func call(_ action: String, _ args: [String: Any] = [:]) async throws -> Data {
    guard let bridge else {
      throw NSError(
        domain: "Litt", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "The local engine is unavailable."])
    }
    let payload = try JSONSerialization.data(withJSONObject: args)
    return try await withCheckedThrowingContinuation { continuation in
      bridge.perform(action, payload: payload) { data, error in
        if let error, !error.isEmpty {
          continuation.resume(
            throwing: NSError(
              domain: "Litt", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
        } else {
          continuation.resume(returning: data ?? Data("{}".utf8))
        }
      }
    }
  }
  func start() {
    guard poll == nil else { return }
    poll = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }
  func stop() {
    poll?.cancel()
    poll = nil
    stopPlayback()
  }
  func refresh() async {
    do {
      state = try JSONDecoder().decode(ArchiveState.self, from: await call("state"))
      if !initialized {
        initialized = true
        if state.last > 0 { day = Date(timeIntervalSince1970: state.last) }
      }
      let next = "\(state.count):\(state.last)"
      if next != signature {
        signature = next
        await load()
      }
    } catch { self.error = error.localizedDescription }
  }
  func load() async {
    generation += 1
    let token = generation
    let start = Calendar.current.startOfDay(for: day)
    let end =
      Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
    do {
      let data = try await call(
        "frames",
        [
          "query": query, "app": app, "from": start.timeIntervalSince1970,
          "to": end.timeIntervalSince1970, "offset": offset, "limit": 200,
        ])
      guard token == generation else { return }
      moments = try JSONDecoder().decode([Moment].self, from: data).reversed()
      if !moments.contains(where: { $0.id == selected }) { selected = moments.last?.id }
      if moments.isEmpty {
        stopPlayback()
        showDetails = false
      }
    } catch { if token == generation { self.error = error.localizedDescription } }
  }
  func filter() async {
    offset = 0
    stopPlayback()
    await load()
  }
  func select(_ id: Int64) { selected = id }
  func move(_ step: Int) {
    guard !moments.isEmpty else { return }
    selected = moments[min(max(index + step, 0), moments.count - 1)].id
  }
  func seek(_ fraction: CGFloat) {
    guard let first = moments.first, let last = moments.last else { return }
    let target = first.time + Double(min(max(fraction, 0), 1)) * (last.time - first.time)
    selected = moments.min(by: { abs($0.time - target) < abs($1.time - target) })?.id
  }
  func stopPlayback() {
    playing = false
    playback?.cancel()
    playback = nil
  }
  func togglePlayback() {
    if playing {
      stopPlayback()
      return
    }
    guard !moments.isEmpty else { return }
    if index == moments.count - 1 { selected = moments.first?.id }
    playing = true
    playback = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        try? await Task.sleep(for: .seconds(1 / self.playbackSpeed))
        if Task.isCancelled { return }
        if self.index >= self.moments.count - 1 {
          self.stopPlayback()
          return
        }
        self.move(1)
      }
    }
  }
  func toggleRecording() async {
    do {
      _ = try await call("toggle")
      await refresh()
      if !state.error.isEmpty { error = state.error }
    } catch { self.error = error.localizedDescription }
  }
  func importImages() async {
    importing = true
    defer { importing = false }
    do {
      let data = try await call("import")
      let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      if result?["cancelled"] as? Bool != true {
        query = ""
        app = ""
        day = Date()
        offset = 0
        signature = ""
        await refresh()
        await load()
      }
    } catch { self.error = error.localizedDescription }
  }
  func exportImage() async {
    guard let selected else { return }
    do { _ = try await call("export", ["id": selected]) } catch {
      self.error = error.localizedDescription
    }
  }
  func deleteMoment() async {
    guard let selected else { return }
    do {
      _ = try await call("delete", ["id": selected])
      images.removeObject(forKey: NSNumber(value: selected))
      showDetails = false
      await refresh()
    } catch { self.error = error.localizedDescription }
  }
  func clear() async {
    do {
      _ = try await call("clear")
      images.removeAllObjects()
      await refresh()
    } catch { self.error = error.localizedDescription }
  }
  func save(_ prefs: Preferences) async {
    do {
      let data = try JSONEncoder().encode(prefs)
      guard let args = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
      }
      _ = try await call("settings", args)
      showSettings = false
      await refresh()
    } catch { self.error = error.localizedDescription }
  }
  func action(_ name: String) async {
    do { _ = try await call(name) } catch { self.error = error.localizedDescription }
  }
  func image(_ m: Moment) -> NSImage? {
    if let image = images.object(forKey: NSNumber(value: m.id)) { return image }
    guard let image = NSImage(contentsOf: root.appendingPathComponent("frames/\(m.id).jpg")) else {
      return nil
    }
    images.setObject(image, forKey: NSNumber(value: m.id))
    return image
  }
  func appIcon(_ bundle: String) -> NSImage? {
    if let icon = icons[bundle] { return icon }
    guard !missingIcons.contains(bundle), !bundle.isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      missingIcons.insert(bundle)
      return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icons[bundle] = icon
    return icon
  }
  func matches(_ box: OCRBox) -> Bool {
    query.split(whereSeparator: { $0.isWhitespace }).contains {
      box.text.localizedCaseInsensitiveContains(String($0))
    }
  }
}
