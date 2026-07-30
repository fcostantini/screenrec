import AppKit

// Compares two images by DECODED PIXELS and reports how many differ.
//
// ⚠️ `md5` of two `screencapture` PNGs is NOT a pixel comparison: identical pixels can encode to
// different bytes, and a first pass in M16-T5 "measured" three distinct menu-bar states that way
// when there were two (docs/07). Anything asserting that two rendered states differ has to decode.
//
// Exit status is the answer, so it composes in a script: 0 identical, 1 different, 2 unusable.
//
// Usage: swift tools/pixdiff.swift a.png b.png [tolerance]
//        tolerance is the per-channel difference ignored (default 0; try 2 for capture noise)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

/// Decoded RGBA bytes at a known layout, so two images are comparable regardless of how each was
/// encoded — the whole point of the tool.
func pixels(of path: String) -> (bytes: [UInt8], width: Int, height: Int) {
    guard let image = NSImage(contentsOfFile: path) else { fail("can't read \(path)") }
    guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("can't decode \(path)")
    }
    let width = source.width, height = source.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("can't build a bitmap for \(path)") }
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (bytes, width, height)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    fail("usage: pixdiff.swift a.png b.png [tolerance]")
}
let first = pixels(of: arguments[arguments.startIndex])
let second = pixels(of: arguments[arguments.startIndex + 1])
let tolerance = Int(arguments.dropFirst(2).first ?? "") ?? 0

guard first.width == second.width, first.height == second.height else {
    print("different size: \(first.width)×\(first.height) vs \(second.width)×\(second.height)")
    exit(1)
}

var differing = 0
var largest = 0
for index in stride(from: 0, to: first.bytes.count, by: 4) {
    var worst = 0
    for channel in 0..<4 {
        worst = max(worst, abs(Int(first.bytes[index + channel]) - Int(second.bytes[index + channel])))
    }
    if worst > tolerance {
        differing += 1
        largest = max(largest, worst)
    }
}

let total = first.width * first.height
let percent = total > 0 ? Double(differing) / Double(total) * 100 : 0
if differing == 0 {
    print("identical: \(total) px, tolerance \(tolerance)")
    exit(0)
}
print(String(
    format: "different: %d/%d px (%.2f%%), largest channel delta %d, tolerance %d",
    differing, total, percent, largest, tolerance))
exit(1)
