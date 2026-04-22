import AppKit
import Observation
import SwiftUI

struct ArchiveState: Decodable {
  var count: Int = 0
  var last: Double = 0
  var recording: Bool = false
  var captureState: String = "Paused"
  var error: String = ""
  var permission: Bool = false
  var settings = Preferences()
  var apps: [AppInfo] = []
  var runningApps: [AppInfo] = []
}
