import AppKit
import ApplicationServices

// Parks the cursor on a menu row and screenshots the open menu once per second — the tool that
// caught M6-T10 (an open-menu rebuild garbling the hover highlight). Open the menu first
// (menudriver open). Needs the Accessibility grant.
//
// Usage: swift tools/hoverprobe.swift <rowTitle> <ticks> <outDir>
//   writes <outDir>/tick-1.png … one per second while hovering <rowTitle>; restores the cursor.

let bundleID = "dev.fcostantini.screenrec.app"
let args = CommandLine.arguments
guard args.count == 4, let ticks = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: hoverprobe <rowTitle> <ticks> <outDir>\n".utf8))
    exit(2)
}
let rowTitle = args[1]
let outDir = args[3]

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    attr(e, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute as String),
          let sv = attr(e, kAXSizeAttribute as String) else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(unsafeBitCast(pv, to: AXValue.self), .cgPoint, &origin)
    AXValueGetValue(unsafeBitCast(sv, to: AXValue.self), .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("no Accessibility grant\n".utf8)); exit(1)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
else { FileHandle.standardError.write(Data("ScreenRec isn't running\n".utf8)); exit(1) }
let axApp = AXUIElementCreateApplication(app.processIdentifier)
guard let extras = attr(axApp, "AXExtrasMenuBar"),
      let item = children(unsafeBitCast(extras, to: AXUIElement.self)).first,
      let menu = children(item).first
else { FileHandle.standardError.write(Data("menu isn't open (run: menudriver open)\n".utf8)); exit(1) }

// The AXMenu's own frame reads zero; union the rows' frames for the capture region, and find the
// target row's center to hover.
var target: CGPoint?
var union = CGRect.null
for row in children(menu) {
    guard let f = frame(row) else { continue }
    union = union.union(f)
    if attr(row, kAXTitleAttribute as String) as? String == rowTitle {
        target = CGPoint(x: f.midX, y: f.midY)
    }
}
guard let target, !union.isNull else {
    FileHandle.standardError.write(Data("row \"\(rowTitle)\" not found\n".utf8)); exit(1)
}
try? FileManager.default.createDirectory(
    atPath: outDir, withIntermediateDirectories: true)

let restore = CGEvent(source: nil)!.location
func moveTo(_ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
        .post(tap: .cghidEventTap)
}
moveTo(target)
let region = "\(Int(union.minX) - 4),\(Int(union.minY) - 4),\(Int(union.width) + 8),\(Int(union.height) + 8)"
for tick in 1...ticks {
    Thread.sleep(forTimeInterval: 1)
    moveTo(target)   // keep the hover alive; some tracking loops idle out without motion
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-R", region, "\(outDir)/tick-\(tick).png"]
    try? capture.run()
    capture.waitUntilExit()
}
moveTo(restore)
print("captured \(ticks) ticks of \"\(rowTitle)\" → \(outDir)")
