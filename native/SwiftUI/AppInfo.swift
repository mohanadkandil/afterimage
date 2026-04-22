import AppKit
import Observation
import SwiftUI

struct AppInfo: Decodable, Identifiable {
  let bundle, name: String
  var id: String { bundle }
}
