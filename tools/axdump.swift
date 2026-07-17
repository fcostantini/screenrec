import AppKit
import ApplicationServices

// Dumps a running app's Accessibility tree — role, title/description/value — for every window.
// The debugging companion to menudriver/settingsdriver: when a control can't be found by role or
// label, this shows how AppKit actually exposes it (SwiftUI labels often live on a sibling, not the
// control). Needs the Accessibility grant (CLAUDE.md, Environment facts).
//
// Usage: swift tools/axdump.swift [bundleID]   (default dev.fcostantini.screenrec.app)

let bundleID = CommandLine.arguments.dropFirst().first ?? "dev.fcostantini.screenrec.app"

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    attr(e, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}
func dump(_ e: AXUIElement, depth: Int) {
    let role = (attr(e, kAXRoleAttribute as String) as? String) ?? "?"
    let bits = [
        attr(e, kAXTitleAttribute as String) as? String,
        (attr(e, kAXDescriptionAttribute as String) as? String).map { "desc=\($0)" },
        attr(e, kAXValueAttribute as String).map { "val=\($0)" },
    ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    print(String(repeating: "  ", count: depth) + role + (bits.isEmpty ? "" : "  [\(bits)]"))
    if depth < 10 { for child in children(e) { dump(child, depth: depth + 1) } }
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("no Accessibility grant\n".utf8)); exit(1)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    FileHandle.standardError.write(Data("\(bundleID) isn't running\n".utf8)); exit(1)
}
let axApp = AXUIElementCreateApplication(app.processIdentifier)
let windows = attr(axApp, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
print("\(bundleID): \(windows.count) window(s)")
for (index, window) in windows.enumerated() {
    print("=== window \(index) ===")
    dump(window, depth: 0)
}
