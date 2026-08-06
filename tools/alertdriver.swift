import AppKit
import ApplicationServices

// Reads and clicks a modal NSAlert's buttons through Accessibility.
//
// menudriver drives the MENU; this drives the alert a menu action puts up (Quit with work in flight,
// Discard Recording…, the naming prompt). A synthetic keystroke can't: it goes to whatever is
// actually frontmost, because an LSUIElement app's alert is drawn inactive and a synthetic press
// confers no activation (docs/07, M21-T3). An NSAlert's controls do carry AXTitle, so AXPress works.
// Needs the Accessibility grant (CLAUDE.md, Environment facts).
//
// Usage: swift tools/alertdriver.swift dump               — the alert's text and buttons
//        swift tools/alertdriver.swift press "Quit Anyway"
//        swift tools/alertdriver.swift type "a name"      — into the first text field
//        (optional trailing bundleID; default dev.fcostantini.screenrec.app)

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    attr(e, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}
func string(_ e: AXUIElement, _ name: String) -> String? { attr(e, name) as? String }

/// Every descendant, parents first — an alert's buttons sit a couple of levels below the window.
func descendants(_ root: AXUIElement, depth: Int = 0) -> [(element: AXUIElement, depth: Int)] {
    guard depth < 8 else { return [] }
    return children(root).flatMap { [($0, depth)] + descendants($0, depth: depth + 1) }
}

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// Matches `kAXTitleAttribute` **or** `kAXDescriptionAttribute`: a SwiftUI button often carries its
/// label only as the description, and matching titles alone can't find it (measured on Settings'
/// `Choose…`).
func firstElement(role: String, title: String? = nil, in windows: [AXUIElement]) -> AXUIElement? {
    for window in windows {
        for (element, _) in descendants(window) where string(element, kAXRoleAttribute as String) == role {
            guard let title else { return element }
            if string(element, kAXTitleAttribute as String) == title { return element }
            if string(element, kAXDescriptionAttribute as String) == title { return element }
        }
    }
    return nil
}

var arguments = CommandLine.arguments.dropFirst()
let command = arguments.first ?? "dump"
arguments = arguments.dropFirst()
let value = arguments.first
let bundleID = arguments.dropFirst().first ?? "dev.fcostantini.screenrec.app"

guard AXIsProcessTrusted() else { fail("no Accessibility grant", 1) }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("\(bundleID) isn't running", 1)
}
let axApp = AXUIElementCreateApplication(app.processIdentifier)
let windows = attr(axApp, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
guard !windows.isEmpty else { fail("no windows — is the alert up?", 2) }

switch command {
case "dump":
    for (index, window) in windows.enumerated() {
        let subrole = string(window, kAXSubroleAttribute as String) ?? "-"
        print("window \(index): \(string(window, kAXTitleAttribute as String) ?? "(untitled)") [\(subrole)]")
        for (element, depth) in descendants(window) {
            let role = string(element, kAXRoleAttribute as String) ?? "?"
            let label = string(element, kAXTitleAttribute as String)
                ?? (attr(element, kAXValueAttribute as String) as? String)
            guard let label, !label.isEmpty else { continue }
            print(String(repeating: "  ", count: depth + 1) + "\(role): \(label)")
        }
    }

case "press":
    guard let title = value else { fail("press needs a button title", 64) }
    // Radio buttons too: a SwiftUI segmented picker's tabs are `AXRadioButton`, and pressing one is
    // the only way to reach Settings' other panes headlessly.
    let pressable = [kAXButtonRole, kAXRadioButtonRole, kAXCheckBoxRole].map { $0 as String }
    guard let button = pressable.lazy
        .compactMap({ firstElement(role: $0, title: title, in: windows) }).first
    else {
        fail("nothing pressable titled \"\(title)\"", 3)
    }
    let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
    guard result == .success else { fail("press failed: \(result.rawValue)", 4) }
    print("pressed \"\(title)\"")

case "type":
    guard let text = value else { fail("type needs a value", 64) }
    guard let field = firstElement(role: kAXTextFieldRole as String, in: windows) else {
        fail("no text field in the alert", 3)
    }
    let result = AXUIElementSetAttributeValue(
        field, kAXValueAttribute as CFString, text as CFTypeRef)
    guard result == .success else { fail("set value failed: \(result.rawValue)", 4) }
    print("typed \"\(text)\"")

default:
    fail("usage: alertdriver.swift [dump | press <title> | type <text>] [bundleID]", 64)
}
