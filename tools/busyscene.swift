import AppKit

// A deterministic full-screen "busy" animation for quality/size calibration (docs/04 §3.6).
// It scrolls a detailed pre-rendered texture and drags a few large opaque shapes across it —
// busy and high-detail, but with COHERENT motion, so it compresses like real screen content
// (scrolling / video) rather than like incompressible noise. That lets each preset's average
// bitrate cap actually bind, so files separate cleanly by preset. Preferred over "loop a video
// in QuickTime": no external file, same content every run.
//
// Usage: swift tools/busyscene.swift [seconds]   (default 10)

let duration = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 10) : 10

/// A detailed, tileable texture (fine multi-frequency color structure) rendered once.
func makeTexture(width: Int, height: Int) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let cell = 10
    for y in stride(from: 0, to: height, by: cell) {
        for x in stride(from: 0, to: width, by: cell) {
            let fx = Double(x), fy = Double(y)
            let r = 0.5 + 0.5 * sin(fx * 0.05) * cos(fy * 0.03)
            let g = 0.5 + 0.5 * sin((fx + fy) * 0.04)
            let b = 0.5 + 0.5 * cos(fx * 0.02 - fy * 0.06)
            ctx.setFillColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
            ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
        }
    }
    return ctx.makeImage()
}

final class BusyView: NSView {
    var frameIndex = 0
    let texture: CGImage?
    let textureSize: CGSize

    init(frame: NSRect, texture: CGImage?) {
        self.texture = texture
        self.textureSize = CGSize(width: texture?.width ?? 1, height: texture?.height ?? 1)
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let texture else { return }
        // Scroll the texture diagonally (coherent, compressible motion), tiling to fill.
        let dx = Double((frameIndex * 6) % Int(textureSize.width))
        let dy = Double((frameIndex * 4) % Int(textureSize.height))
        for ox in stride(from: -dx, to: bounds.width, by: textureSize.width) {
            for oy in stride(from: -dy, to: bounds.height, by: textureSize.height) {
                ctx.draw(texture, in: CGRect(x: ox, y: oy, width: textureSize.width, height: textureSize.height))
            }
        }
        // A few large opaque squares gliding across — they occlude/reveal texture, adding the
        // moderate unpredictability real content has (new pixels appearing) without going random.
        let f = Double(frameIndex)
        for i in 0..<6 {
            let phase = f * 0.02 + Double(i)
            let x = (0.5 + 0.5 * sin(phase * 1.3)) * bounds.width
            let y = (0.5 + 0.5 * cos(phase * 0.9)) * bounds.height
            ctx.setFillColor(NSColor(hue: CGFloat((Double(i) / 6).truncatingRemainder(dividingBy: 1)),
                                     saturation: 0.9, brightness: 0.9, alpha: 1).cgColor)
            ctx.fill(CGRect(x: x - 120, y: y - 120, width: 240, height: 240))
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.main else { exit(1) }
let scale = screen.backingScaleFactor
let texture = makeTexture(width: Int(screen.frame.width * scale * 0.6), height: Int(screen.frame.height * scale * 0.6))
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = .screenSaver
let view = BusyView(frame: screen.frame, texture: texture)
window.contentView = view
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
    view.frameIndex += 1
    view.needsDisplay = true
}
RunLoop.current.add(timer, forMode: .common)
RunLoop.current.run(until: Date().addingTimeInterval(duration))
