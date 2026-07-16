import AppCore
import Carbon.HIToolbox
import Foundation
import SwiftUI

/// Registers the global save-replay shortcut via Carbon `RegisterEventHotKey` — the one global
/// hotkey API that needs no Accessibility/Input-Monitoring grant (02 §9). One shortcut at a
/// time; registered only while replay is armed.
final class HotkeyCenter {
    var onHotkey: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5352_5259  // 'SRRY'

    /// Registers `hotkey`, replacing any previous one; nil unregisters (and returns true).
    /// False means the system refused the combo (taken by another app) — the caller must tell
    /// the user, because every UI surface advertises the shortcut as live.
    @discardableResult
    func setHotkey(_ hotkey: ReplayHotkey?) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let hotkey else { return true }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode), UInt32(hotkey.modifiers), id,
            GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
        return status == noErr && ref != nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in center.onHotkey?() }
                return noErr
            },
            1, &eventType, selfPointer, &handlerRef)
    }
}

/// Human-readable form of a `ReplayHotkey` (the settings pill, the menu hint) and its SwiftUI
/// key equivalent. Key codes are Carbon kVK_* constants; the map covers the keys a shortcut
/// plausibly uses, with a stated fallback rather than a silent blank.
enum HotkeyDisplay {
    static func string(for hotkey: ReplayHotkey) -> String {
        modifierSymbols(for: hotkey.modifiers) + (keyNames[hotkey.keyCode] ?? "key \(hotkey.keyCode)")
    }

    /// The key as a SwiftUI equivalent for menu display; nil for keys SwiftUI can't represent.
    /// Special keys map to their semantic constants — a literal "↩" character is not Return.
    static func keyEquivalent(for hotkey: ReplayHotkey) -> KeyEquivalent? {
        switch hotkey.keyCode {
        case kVK_Return: return .return
        case kVK_Tab: return .tab
        case kVK_Space: return .space
        case kVK_LeftArrow: return .leftArrow
        case kVK_RightArrow: return .rightArrow
        case kVK_UpArrow: return .upArrow
        case kVK_DownArrow: return .downArrow
        default:
            guard let name = keyNames[hotkey.keyCode], name.count == 1,
                  let character = name.lowercased().first else { return nil }
            return KeyEquivalent(character)
        }
    }

    /// The Carbon modifier mask as SwiftUI modifiers — one decoder, shared by every view.
    static func eventModifiers(for hotkey: ReplayHotkey) -> SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if hotkey.modifiers & cmdKey != 0 { modifiers.insert(.command) }
        if hotkey.modifiers & optionKey != 0 { modifiers.insert(.option) }
        if hotkey.modifiers & controlKey != 0 { modifiers.insert(.control) }
        if hotkey.modifiers & shiftKey != 0 { modifiers.insert(.shift) }
        return modifiers
    }

    static func modifierSymbols(for carbonModifiers: Int) -> String {
        var symbols = ""
        if carbonModifiers & controlKey != 0 { symbols += "⌃" }
        if carbonModifiers & optionKey != 0 { symbols += "⌥" }
        if carbonModifiers & shiftKey != 0 { symbols += "⇧" }
        if carbonModifiers & cmdKey != 0 { symbols += "⌘" }
        return symbols
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
