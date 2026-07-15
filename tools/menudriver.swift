import AppKit
import ApplicationServices
import Foundation

// Drives ScreenRec's menu-bar item through the Accessibility API, so menu states can be
// inspected and exercised without a human clicking (docs/03 marks the M4/M5 menu verifies
// "(human)" precisely because they couldn't be). Needs the Accessibility grant — see the
// Environment facts in CLAUDE.md.
//
// 🔴 WHAT THIS TOOL CANNOT TELL YOU: **whether a window came to the front.**
// A synthetic click doesn't confer activation the way a real one does, so after
// `click "Settings…"` the app stays un-frontmost and the window looks like it opened behind
// everything — *no matter what the app does*. That is this tool's artifact, not the app's
// behaviour: it cost an hour and a design change chasing a bug that didn't exist, until Franco
// said "the menu opens fine for me" (M4-T4, 2026-07-15). Window activation is a human check.
// What IS trustworthy here: menu structure, titles, checkmarks, enabled/disabled, and that a
// click reached its target.
//
//   swift tools/menudriver.swift dump            structure of the open menu, one item per line
//   swift tools/menudriver.swift open            open it and leave it open (then screencapture)
//   swift tools/menudriver.swift click "Pause"   open, click an item by title, dismiss
//   swift tools/menudriver.swift dismiss         close it
//
// `dump` is the useful one: it makes docs/06's menu order, checkmarks and disabled rows
// *assertable* rather than a screenshot someone has to squint at.

let bundleID = "dev.fcostantini.screenrec.app"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("menudriver: \(message)\n".utf8))
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}

/// Narrows a CF attribute value to a concrete AX type, failing loudly if the API ever breaks
/// its own contract. Loudly is the point: a silent fallback here would report an empty menu —
/// indistinguishable from a menu that really is empty, which is the false negative this
/// project keeps getting bitten by (02 §4's `updateConfiguration`, the `--nil-follow` window).
func narrow<T>(_ value: CFTypeRef, _ typeID: CFTypeID, _ what: String) -> T {
    guard CFGetTypeID(value) == typeID else { fail("\(what) wasn't the type the AX API promises") }
    return unsafeBitCast(value, to: T.self)
}

/// The app's status item. `AXExtrasMenuBar` is the menu-bar-extras bar — distinct from
/// `AXMenuBar`, which is the app's main menu and which an LSUIElement app doesn't show.
func statusItem() -> AXUIElement {
    guard AXIsProcessTrusted() else {
        fail("no Accessibility grant — System Settings → Privacy & Security → Accessibility")
    }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    else { fail("ScreenRec isn't running (open dist/ScreenRec.app)") }

    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    guard let extras = attribute(axApp, "AXExtrasMenuBar") else { fail("no AXExtrasMenuBar") }
    let bar: AXUIElement = narrow(extras, AXUIElementGetTypeID(), "AXExtrasMenuBar")
    guard let item = children(bar).first else { fail("no status item") }
    return item
}

func frameCenter(_ element: AXUIElement) -> CGPoint {
    var origin = CGPoint.zero, size = CGSize.zero
    if let value = attribute(element, kAXPositionAttribute as String) {
        AXValueGetValue(narrow(value, AXValueGetTypeID(), "AXPosition"), .cgPoint, &origin)
    }
    if let value = attribute(element, kAXSizeAttribute as String) {
        AXValueGetValue(narrow(value, AXValueGetTypeID(), "AXSize"), .cgSize, &size)
    }
    return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
}

/// Opens the menu with a synthetic click.
///
/// Not `AXPress`: on a menu-bar item that returns `.success` and does nothing at all — menu
/// tracking runs its own modal event loop that the AX action never enters. The same shape as
/// SCK's `updateConfiguration` reporting OK on a dead device (02 §4): a success code is not
/// evidence the thing happened. Verify by looking, not by the return value.
func openMenu() {
    let center = frameCenter(statusItem())
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
            mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
            mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(250_000)                      // let the menu finish opening before anyone reads it
}

func dismissMenu() {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?  // Escape
        .post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    usleep(150_000)
}

/// The `AXMenu` hanging off the status item. It exists while the menu is closed but is only
/// populated once it opens, so every reader here opens first.
func openMenuElement() -> AXUIElement {
    openMenu()
    guard let menu = children(statusItem()).first else { fail("status item has no menu") }
    return menu
}

/// A submenu's items only exist in the accessibility tree once the submenu has been opened —
/// SwiftUI/AppKit build them lazily. Read them without opening and you get an empty list that is
/// indistinguishable from a genuinely empty submenu.
///
/// That is not hypothetical: this printed an empty Microphone submenu for a menu that had two
/// devices in it, and the empty reading was taken as an app regression until a human's
/// screenshot disproved it. So: open it, and if it still reads empty, say `(unread)` rather than
/// print nothing and let it pass for fact. Same family as AXPress-returns-success-and-does-
/// nothing above, and as 02 §4's `updateConfiguration` — silence must never render as evidence.
func openedChildren(of item: AXUIElement, _ submenu: AXUIElement) -> [AXUIElement]? {
    for _ in 0..<10 {
        let kids = children(submenu)
        if !kids.isEmpty { return kids }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        usleep(80_000)
    }
    return children(submenu).isEmpty ? nil : children(submenu)
}

func describe(_ menu: AXUIElement, indent: String = "  ") {
    for item in children(menu) {
        let role = attribute(item, kAXRoleAttribute as String) as? String ?? "?"
        let title = attribute(item, kAXTitleAttribute as String) as? String ?? ""
        // An empty-titled menu item is how AppKit represents a separator.
        guard !(role == "AXMenuItem" && title.isEmpty) else { print("\(indent)---"); continue }

        let enabled = (attribute(item, kAXEnabledAttribute as String) as? Bool) ?? true
        let mark = attribute(item, "AXMenuItemMarkChar") as? String ?? ""
        let shortcut = attribute(item, "AXMenuItemCmdChar") as? String ?? ""

        var line = "\(indent)\(mark.isEmpty ? " " : mark) \(title)"
        if !shortcut.isEmpty { line += "  [⌘\(shortcut)]" }
        if !enabled { line += "  (disabled)" }
        print(line)

        // A submenu is a child AXMenu; recurse so `Display ▸` shows its entries.
        for sub in children(item) where
            (attribute(sub, kAXRoleAttribute as String) as? String) == "AXMenu" {
            guard openedChildren(of: item, sub) != nil else {
                print("\(indent)    (unread — submenu never populated)")
                continue
            }
            describe(sub, indent: indent + "    ")
        }
    }
}

/// Depth-first search for a titled item, so submenu entries ("Balanced", a microphone's name)
/// are reachable and not just the top level.
func find(_ menu: AXUIElement, title: String) -> AXUIElement? {
    for item in children(menu) {
        if (attribute(item, kAXTitleAttribute as String) as? String) == title { return item }
        for sub in children(item)
        where (attribute(sub, kAXRoleAttribute as String) as? String) == "AXMenu" {
            if let hit = find(sub, title: title) { return hit }
        }
    }
    return nil
}

func click(title: String) {
    let menu = openMenuElement()
    guard let item = find(menu, title: title) else {
        dismissMenu()
        fail("no menu item titled \"\(title)\"")
    }
    // Menu *items* do respond to AXPress once their menu is open — unlike the bar item.
    guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
        dismissMenu()
        fail("couldn't press \"\(title)\"")
    }
    print("clicked \"\(title)\"")
}

switch CommandLine.arguments.dropFirst().first {
case "dump":
    describe(openMenuElement())
    dismissMenu()
case "open":
    openMenu()
case "dismiss":
    dismissMenu()
case "click":
    guard let title = CommandLine.arguments.dropFirst(2).first else { fail("click needs a title") }
    click(title: title)
default:
    fail("usage: menudriver.swift <dump|open|dismiss|click \"Title\">")
}
