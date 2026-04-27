import AppKit
import SwiftUI

/// Wheel input belongs to the timeline and advances the selected recording.
struct HorizontalWheelSupport: NSViewRepresentable {
  let move: (Int) -> Void
  func makeNSView(context: Context) -> WheelRegion { WheelRegion(move: move) }
  func updateNSView(_ nsView: WheelRegion, context: Context) { nsView.move = move }
  static func dismantleNSView(_ nsView: WheelRegion, coordinator: ()) { nsView.stop() }

  final class WheelRegion: NSView {
    var move: (Int) -> Void
    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var lastEvent: TimeInterval = 0
    init(move: @escaping (Int) -> Void) {
      self.move = move
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        guard let self, event.window == self.window,
          self.bounds.contains(self.convert(event.locationInWindow, from: nil))
        else { return event }
        self.consume(
          deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
          precise: event.hasPreciseScrollingDeltas, timestamp: event.timestamp)
        return nil
      }
    }
    func consume(deltaX: CGFloat, deltaY: CGFloat, precise: Bool, timestamp: TimeInterval) {
      if timestamp - lastEvent > 0.3 { accumulated = 0 }
      lastEvent = timestamp
      let delta = abs(deltaX) > abs(deltaY) ? deltaX : deltaY
      if accumulated * delta > 0 { accumulated = 0 }
      accumulated -= delta
      let threshold: CGFloat = precise ? 24 : 1
      let steps = Int(accumulated / threshold)
      guard steps != 0 else { return }
      accumulated -= CGFloat(steps) * threshold
      move(max(-5, min(5, steps)))
    }
    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
