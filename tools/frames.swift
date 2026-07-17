import AVFoundation
import AppKit

// Extracts frames from a recording at a range of timestamps, as PNGs — the visual complement to
// probe.swift (which only reads track metadata). Used to check clip *content*: e.g. that a replay
// holds the right seconds, or that a menu-rendering bug shows up frame by frame.
//
// Usage: swift tools/frames.swift <file> <startSec> <endSec> <stepSec> <outDir>
//   writes <outDir>/f<start>.png … one per step; outDir is created if absent.

let args = CommandLine.arguments
guard args.count == 6, let start = Double(args[2]), let end = Double(args[3]),
      let step = Double(args[4]), step > 0 else {
    FileHandle.standardError.write(Data("usage: frames <file> <start> <end> <step> <outDir>\n".utf8))
    exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let outDir = URL(fileURLWithPath: args[5], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

// The generate call is async; a semaphore keeps this sequential script simple.
func frame(at time: CMTime) -> CGImage? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: CGImage?
    generator.generateCGImageAsynchronously(for: time) { image, _, _ in
        result = image
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

var written = 0
var t = start
while t <= end {
    if let cg = frame(at: CMTime(seconds: t, preferredTimescale: 600)),
       let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
        try? png.write(to: outDir.appendingPathComponent(String(format: "f%06.2f.png", t)))
        written += 1
    }
    t += step
}
print("wrote \(written) frames to \(outDir.path)")
