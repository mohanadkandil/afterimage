import AppKit
import Observation
import SwiftUI

struct Preferences: Codable, Equatable {
  var interval: Int = 2
  var retentionDays: Int = 14
  var excluded: [String] = []
  var displayId: UInt32 = 0
}
