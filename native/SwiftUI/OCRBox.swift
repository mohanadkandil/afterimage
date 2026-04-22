import AppKit
import Observation
import SwiftUI

struct OCRBox: Decodable {
  let text: String
  let x, y, w, h: Double
}
