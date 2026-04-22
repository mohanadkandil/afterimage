import AppKit
import Observation
import SwiftUI

struct Moment: Decodable, Identifiable {
  let id: Int64
  let time: Double
  let app, bundle, title, text, source: String
  let width, height: Int
  let boxes: [OCRBox]
  var date: Date { Date(timeIntervalSince1970: time) }
}
