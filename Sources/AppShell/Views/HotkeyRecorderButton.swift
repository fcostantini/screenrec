import AppCore
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The shortcut pill in Settings: click, type a combo, done. Esc cancels. A combo must carry
/// ⌥ or ⌃ — plain-⌘ combos are the system's and other apps' vocabulary (⌘C, ⌘Tab, ⌘Space…),
/// and a Carbon hotkey would hijack them globally while replay is armed.
struct HotkeyRecorderButton: View {
    @Binding var hotkey: Hotkey
    /// Names this shortcut for VoiceOver (there are two now — replay and record, M9-T4).
    var accessibilityName = "Shortcut"
    /// The registered hotkey intercepts its own combo before any local monitor sees it, so the
    /// owner must suspend it while the recorder listens and restore it after.
    var suspendGlobalHotkey: () -> Void = {}
    var restoreGlobalHotkey: () -> Void = {}

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Type shortcut…" : HotkeyDisplay.string(for: hotkey)) {
            isRecording ? stopRecording() : startRecording()
        }
        .accessibilityLabel("\(accessibilityName): \(HotkeyDisplay.string(for: hotkey))")
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        suspendGlobalHotkey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }
            guard event.keyCode != kVK_Escape else { return nil }   // cancel, keep the old combo
            let modifiers = carbonModifiers(from: event.modifierFlags)
            guard modifiers & (optionKey | controlKey) != 0 else { return nil }
            hotkey = Hotkey(keyCode: Int(event.keyCode), modifiers: modifiers)
            return nil          // consumed — the combo must not also type into the window
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        restoreGlobalHotkey()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        return carbon
    }
}
