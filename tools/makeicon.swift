import AppKit

// Renders the ScreenRec app icon master (1024×1024 PNG) to stdout's target path.
// The icon is drawn in code because there's no Xcode here for an asset catalog and a
// hand-drawn PNG has no source of truth. Scripts/bundle.sh (or make-icns below) turns the
// master into AppIcon.icns via iconutil.
//
//   swift tools/makeicon.swift <output.png>
//
// Motif: a display with a red record dot — the one candidate that reads as a *screen*
// recorder, which is what has to be told apart in the Screen Recording permission list.

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-master.png"

let ink = NSColor(calibratedWhite: 0.13, alpha: 1)
let bezel = NSColor(calibratedWhite: 0.82, alpha: 1)
let red = NSColor(calibratedRed: 0.88, green: 0.24, blue: 0.19, alpha: 1)

func scaled(_ rect: NSRect) -> NSRect {
    // The candidates were drawn on a 512 grid; keep those proportions at 1024.
    NSRect(x: rect.origin.x * 2, y: rect.origin.y * 2,
           width: rect.size.width * 2, height: rect.size.height * 2)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let full = NSRect(x: 0, y: 0, width: size, height: size)
ink.setFill()
NSBezierPath(roundedRect: full.insetBy(dx: 48, dy: 48), xRadius: 224, yRadius: 224).fill()

let screen = scaled(NSRect(x: 108, y: 150, width: 296, height: 208))
bezel.setStroke()
let display = NSBezierPath(roundedRect: screen, xRadius: 36, yRadius: 36)
display.lineWidth = 40
display.stroke()

red.setFill()
NSBezierPath(ovalIn: scaled(NSRect(x: 218, y: 208, width: 76, height: 76))).fill()

bezel.setFill()
NSBezierPath(roundedRect: scaled(NSRect(x: 226, y: 112, width: 60, height: 20)),
             xRadius: 20, yRadius: 20).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("makeicon: failed to encode PNG\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: output))
    print(output)
} catch {
    FileHandle.standardError.write(Data("makeicon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
