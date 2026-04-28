import Foundation

/// Consecutive samples from one app form a single band; real recording gaps stay empty.
struct TimelineSpan: Identifiable {
  let first: Moment
  var end: Double
  var id: Int64 { first.id }

  static func grouped(_ moments: [Moment]) -> [TimelineSpan] {
    var spans: [TimelineSpan] = []
    for (index, moment) in moments.enumerated() {
      let end =
        index + 1 < moments.count
        ? min(moments[index + 1].time, moment.time + 30) : moment.time + 1
      if let last = spans.last, last.first.bundle == moment.bundle, last.end >= moment.time {
        spans[spans.count - 1].end = end
      } else {
        spans.append(TimelineSpan(first: moment, end: end))
      }
    }
    return spans
  }
}
