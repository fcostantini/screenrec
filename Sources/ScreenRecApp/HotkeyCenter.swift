import AppCore
import Carbon.HIToolbox
import Foundation
import SwiftUI

/// Every Carbon hotkey this app registers.
///
/// ⚠️ Ids are process-global, so two features sharing a number silently unregister each other.
/// The guarantee is the enum, not the list: duplicate raw values don't compile.
enum HotkeyID: UInt32 {
    case saveReplay = 1
    case toggleRecording = 2
    case togglePause = 3
    /// Esc during the count-in — registered only while the beat runs, since it swallows Esc
    /// system-wide (M18-T4).
    case cancelCountIn = 4
}

/// Registers global shortcuts via Carbon `RegisterEventHotKey` — the one global hotkey API that
/// needs no Accessibility/Input-Monitoring grant (02 §9). Holds several at once, keyed by id
/// (M9-T4: save-replay and start/stop record), each with its own action; the shared handler
/// dispatches by the fired hotkey's id.
final class HotkeyCenter {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5352_5259  // 'SRRY'

    /// Registers `hotkey` under `id`, replacing any previous one for that id; `action` fires on the
    /// main actor when the combo is pressed. A nil hotkey unregisters `id` (and returns true).
    /// False means the system refused the combo (taken by another app) — the caller must tell the
    /// user, because every UI surface advertises the shortcut as live.
    @discardableResult
    func setHotkey(
        _ hotkey: Hotkey?, id which: HotkeyID, action: @escaping @MainActor () -> Void = {}
    ) -> Bool {
        let id = which.rawValue
        if let existing = refs[id] {
            UnregisterEventHotKey(existing)
            refs[id] = nil
        }
        actions[id] = nil
        guard let hotkey else { return true }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode), UInt32(hotkey.modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        actions[id] = action
        return true
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var fired = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &fired)
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                let id = fired.id
                Task { @MainActor in center.actions[id]?() }
                return noErr
            },
            1, &eventType, selfPointer, &handlerRef)
    }
}

/// Human-readable form of a `Hotkey` (the settings pill, the menu hint) and its SwiftUI
/// key equivalent. Key codes are Carbon kVK_* constants; the map covers the keys a shortcut
/// plausibly uses, with a stated fallback rather than a silent blank.
enum HotkeyDisplay {
    static func string(for hotkey: Hotkey) -> String {
        modifierSymbols(for: hotkey.modifiers) + (keyNames[hotkey.keyCode] ?? "key \(hotkey.keyCode)")
    }

    /// The key as a SwiftUI equivalent for menu display; nil for keys SwiftUI can't represent.
    /// Special keys map to their semantic constants — a literal "↩" character is not Return.
    static func keyEquivalent(for hotkey: Hotkey) -> KeyEquivalent? {
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
    static func eventModifiers(for hotkey: Hotkey) -> SwiftUI.EventModifiers {
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
