import AppKit
import ApplicationServices

// Drives the app's Settings *window* via Accessibility — the complement to menudriver.swift, which
// drives the menu-bar *menu*. Screenshots the window, or presses a checkbox and reports its value
// change. Open Settings first (menudriver click "Settings…"). Needs the Accessibility grant.
//
//   swift tools/settingsdriver.swift shot <out.png>   screenshot the Settings window
//   swift tools/settingsdriver.swift toggle           press the sole checkbox, print before → after
//
// The Settings form has exactly one AXCheckBox (Launch at login); its label is a sibling
// AXStaticText, so the checkbox is found by role, not by title.

let bundleID = "dev.fcostantini.screenrec.app"
let windowTitle = "ScreenRec Settings"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("settingsdriver: \(message)\n".utf8)); exit(1)
}
func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    attr(e, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}
func title(_ e: AXUIElement) -> String? { attr(e, kAXTitleAttribute as String) as? String }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute as String),
          let sv = attr(e, kAXSizeAttribute as String) else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(unsafeBitCast(pv, to: AXValue.self), .cgPoint, &origin)
    AXValueGetValue(unsafeBitCast(sv, to: AXValue.self), .cgSize, &size)
    return CGRect(origin: origin, size: size)
}
func firstDescendant(_ e: AXUIElement, role: String) -> AXUIElement? {
    if attr(e, kAXRoleAttribute as String) as? String == role { return e }
    for child in children(e) {
        if let hit = firstDescendant(child, role: role) { return hit }
    }
    return nil
}

guard AXIsProcessTrusted() else { fail("no Accessibility grant") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
else { fail("ScreenRec isn't running") }
let axApp = AXUIElementCreateApplication(app.processIdentifier)
let windows = attr(axApp, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
guard let settings = windows.first(where: { title($0) == windowTitle })
else { fail("Settings window isn't open (run: menudriver click \"Settings…\")") }

switch CommandLine.arguments.dropFirst().first {
case "shot":
    guard let out = CommandLine.arguments.dropFirst(2).first else { fail("shot needs an output path") }
    guard let f = frame(settings) else { fail("no window frame") }
    let region = "\(Int(f.minX) - 2),\(Int(f.minY) - 2),\(Int(f.width) + 4),\(Int(f.height) + 4)"
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-R", region, out]
    try? capture.run()
    capture.waitUntilExit()
    print("shot \(region) → \(out)")

case "toggle":
    guard let box = firstDescendant(settings, role: "AXCheckBox") else { fail("no checkbox in Settings") }
    let before = (attr(box, kAXValueAttribute as String) as? Int) ?? -1
    AXUIElementPerformAction(box, kAXPressAction as CFString)
    usleep(500_000)
    let after = (attr(box, kAXValueAttribute as String) as? Int) ?? -1
    print("toggle: \(before) → \(after)")

default:
    fail("usage: settingsdriver shot <out.png> | toggle")
}
