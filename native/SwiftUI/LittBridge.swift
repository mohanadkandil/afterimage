import AppKit
import Observation
import SwiftUI

@objc public protocol LittBridge: AnyObject {
  func perform(_ action: String, payload: Data, completion: @escaping (Data?, String?) -> Void)
}
