import AppKit
import SwiftUI

/// Converts a conventional vertical mouse wheel to horizontal timeline scrolling.
struct HorizontalWheelSupport: NSViewRepresentable {
  func makeNSView(context: Context) -> WheelRegion { WheelRegion() }
  func updateNSView(_ nsView: WheelRegion, context: Context) {}
  static func dismantleNSView(_ nsView: WheelRegion, coordinator: ()) { nsView.stop() }

  final class WheelRegion: NSView {
    private var monitor: Any?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        guard let self, event.window == self.window,
          self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
          !event.hasPreciseScrollingDeltas
        else { return event }
        guard let scroll = self.timelineScroll() else { return event }
        let clip = scroll.contentView
        let maximum = max(0, (scroll.documentView?.bounds.width ?? 0) - clip.bounds.width)
        let delta =
          abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
          ? event.scrollingDeltaX : event.scrollingDeltaY
        clip.scroll(
          to: NSPoint(
            x: min(maximum, max(0, clip.bounds.origin.x - delta * 12)), y: clip.bounds.origin.y))
        scroll.reflectScrolledClipView(clip)
        return nil
      }
    }
    private func timelineScroll() -> NSScrollView? {
      var ancestor = superview
      for _ in 0..<8 {
        guard let view = ancestor else { break }
        if let scroll = findScroll(view) { return scroll }
        ancestor = view.superview
      }
      return nil
    }
    private func findScroll(_ view: NSView) -> NSScrollView? {
      if let scroll = view as? NSScrollView,
        scroll.bounds.contains(scroll.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)),
        (scroll.documentView?.bounds.width ?? 0) > scroll.contentView.bounds.width
      {
        return scroll
      }
      for child in view.subviews { if let scroll = findScroll(child) { return scroll } }
      return nil
    }
    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
