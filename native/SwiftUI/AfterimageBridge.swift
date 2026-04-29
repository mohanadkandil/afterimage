import AppKit
import Observation
import SwiftUI

@objc public protocol AfterimageBridge: AnyObject {
  func perform(_ action: String, payload: Data, completion: @escaping (Data?, String?) -> Void)
}
