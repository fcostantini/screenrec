import AppKit
import ApplicationServices

// Prints a menu-bar status item's real screen frame, so a screenshot can crop exactly it.
//
// ⚠️ AppleScript's `position of menu bar item 1` returns 0,24 — useless. The frame only comes from
// the AX `kAXExtrasMenuBarAttribute` on the owning app (docs/07, M16-T5). Without it you cannot crop
// a menu bar full of live third-party items, and diffing a wide strip is meaningless: CPU% and
// network counters change every second. Needs the Accessibility grant (CLAUDE.md, Environment facts).
//
// Usage: swift tools/itemframe.swift [bundleID]      — "x y w h", ready for screencapture -R
//        swift tools/itemframe.swift --rect [bundleID]  — "x,y,w,h" exactly as -R wants it

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

// Position and size arrive boxed in an `AXValue`, not as plain numbers. Both casts below are
// unconditional because Swift rejects a conditional one here as never failing; the real check is
// `AXValueGetValue`, which returns false if the box holds another type.

func point(_ e: AXUIElement, _ name: String) -> CGPoint? {
    guard let raw = attr(e, name) else { return nil }
    var result = CGPoint.zero
    guard AXValueGetValue(raw as! AXValue, .cgPoint, &result) else { return nil }
    return result
}

func size(_ e: AXUIElement, _ name: String) -> CGSize? {
    guard let raw = attr(e, name) else { return nil }
    var result = CGSize.zero
    guard AXValueGetValue(raw as! AXValue, .cgSize, &result) else { return nil }
    return result
}

var arguments = CommandLine.arguments.dropFirst()
let wantsRect = arguments.first == "--rect"
if wantsRect { arguments = arguments.dropFirst() }
let bundleID = arguments.first ?? "dev.fcostantini.screenrec.app"

guard AXIsProcessTrusted() else { fail("no Accessibility grant", 1) }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("\(bundleID) isn't running", 1)
}
let axApp = AXUIElementCreateApplication(app.processIdentifier)
guard let raw = attr(axApp, kAXExtrasMenuBarAttribute as String) else {
    fail("no menu bar extra — the app may not have installed its status item yet", 2)
}
// Invariant: the attribute carries an AXUIElement, and the compiler rejects a conditional cast
// here as one that cannot fail.
let extras = raw as! AXUIElement
let items = attr(extras, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
guard let item = items.first else { fail("the menu bar extra has no items", 2) }
guard let origin = point(item, kAXPositionAttribute as String),
      let extent = size(item, kAXSizeAttribute as String)
else { fail("the item reported no frame", 3) }

if wantsRect {
    print("\(Int(origin.x)),\(Int(origin.y)),\(Int(extent.width)),\(Int(extent.height))")
} else {
    print("\(Int(origin.x)) \(Int(origin.y)) \(Int(extent.width)) \(Int(extent.height))")
}
