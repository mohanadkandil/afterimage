import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: benchmark-codecs.swift inputs.json results.json")
}
let paths = try JSONDecoder().decode(
  [String].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
func words(_ image: CGImage) throws -> Set<String> {
  let r = VNRecognizeTextRequest()
  r.recognitionLevel = .accurate
  r.usesLanguageCorrection = true
  try VNImageRequestHandler(cgImage: image).perform([r])
  return Set(
    (r.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
      .lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
}
var results: [[String: Any]] = []
for path in paths {
  let input = try Data(contentsOf: URL(fileURLWithPath: path))
  let source = CGImageSourceCreateWithData(input as CFData, nil)!
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
  let reference = try words(image)
  for (codec, quality) in [("public.jpeg", 0.70), ("public.heic", 0.86), ("public.heic", 0.70)] {
    let output = NSMutableData()
    let start = CFAbsoluteTimeGetCurrent()
    guard let encoder = CGImageDestinationCreateWithData(output, codec as CFString, 1, nil) else {
      continue
    }
    CGImageDestinationAddImage(
      encoder, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(encoder) else { continue }
    let encodeMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
    let decodeStart = CFAbsoluteTimeGetCurrent()
    let decoded = CGImageSourceCreateImageAtIndex(
      CGImageSourceCreateWithData(output, nil)!, 0,
      [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
    let decodeMs = (CFAbsoluteTimeGetCurrent() - decodeStart) * 1000
    let recognized = try words(decoded)
    results.append([
      "codec": codec, "quality": quality, "originalBytes": input.count, "bytes": output.length,
      "encodeMs": encodeMs, "decodeMs": decodeMs,
      "ocrTokenRecall": Double(reference.intersection(recognized).count)
        / Double(max(1, reference.count)),
    ])
  }
}
let data = try JSONSerialization.data(
  withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("Completed \(results.count) codec comparisons across \(paths.count) screenshots")
