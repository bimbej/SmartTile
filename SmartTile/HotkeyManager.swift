import Carbon
import AppKit

/// Global keyboard shortcut registration via Carbon Events.
/// Supports multiple named hotkeys with persistence.
final class HotkeyManager {

    // MARK: - KeyCombo

    struct KeyCombo: Equatable, Codable {
        let keyCode: UInt32
        let modifiers: UInt32

        var displayName: String {
            var parts: [String] = []
            if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
            if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
            if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
            if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
            parts.append(Self.keyName(for: keyCode))
            return parts.joined()
        }

        static func keyName(for keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_ANSI_A: return "A"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_C: return "C"
            case kVK_ANSI_D: return "D"
            case kVK_ANSI_E: return "E"
            case kVK_ANSI_F: return "F"
            case kVK_ANSI_G: return "G"
            case kVK_ANSI_H: return "H"
            case kVK_ANSI_I: return "I"
            case kVK_ANSI_J: return "J"
            case kVK_ANSI_K: return "K"
            case kVK_ANSI_L: return "L"
            case kVK_ANSI_M: return "M"
            case kVK_ANSI_N: return "N"
            case kVK_ANSI_O: return "O"
            case kVK_ANSI_P: return "P"
            case kVK_ANSI_Q: return "Q"
            case kVK_ANSI_R: return "R"
            case kVK_ANSI_S: return "S"
            case kVK_ANSI_T: return "T"
            case kVK_ANSI_U: return "U"
            case kVK_ANSI_V: return "V"
            case kVK_ANSI_W: return "W"
            case kVK_ANSI_X: return "X"
            case kVK_ANSI_Y: return "Y"
            case kVK_ANSI_Z: return "Z"
            case kVK_ANSI_0: return "0"
            case kVK_ANSI_1: return "1"
            case kVK_ANSI_2: return "2"
            case kVK_ANSI_3: return "3"
            case kVK_ANSI_4: return "4"
            case kVK_ANSI_5: return "5"
            case kVK_ANSI_6: return "6"
            case kVK_ANSI_7: return "7"
            case kVK_ANSI_8: return "8"
            case kVK_ANSI_9: return "9"
            case kVK_Space: return "Space"
            case kVK_Return: return "↩"
            case kVK_Tab: return "⇥"
            case kVK_Escape: return "⎋"
            case kVK_F1: return "F1"
            case kVK_F2: return "F2"
            case kVK_F3: return "F3"
            case kVK_F4: return "F4"
            case kVK_F5: return "F5"
            case kVK_F6: return "F6"
            case kVK_F7: return "F7"
            case kVK_F8: return "F8"
            case kVK_F9: return "F9"
            case kVK_F10: return "F10"
            case kVK_F11: return "F11"
            case kVK_F12: return "F12"
            case kVK_ANSI_Minus: return "-"
            case kVK_ANSI_Equal: return "="
            case kVK_ANSI_LeftBracket: return "["
            case kVK_ANSI_RightBracket: return "]"
            case kVK_ANSI_Semicolon: return ";"
            case kVK_ANSI_Quote: return "'"
            case kVK_ANSI_Comma: return ","
            case kVK_ANSI_Period: return "."
            case kVK_ANSI_Slash: return "/"
            case kVK_ANSI_Backslash: return "\\"
            default: return "Key(\(keyCode))"
            }
        }

        /// Convert NSEvent modifier flags to Carbon modifier mask
        static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
            var mods: UInt32 = 0
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            return mods
        }
    }

    // MARK: - Hotkey Slot

    enum HotkeyAction: String, Codable, CaseIterable {
        case arrange = "arrange"
        case grid = "grid"
        case save = "save"

        var displayName: String {
            switch self {
            case .arrange: return "Smart Arrange"
            case .grid: return "Grid Tile"
            case .save: return "Save Layout"
            }
        }

        /// Stable numeric ID for Carbon hotkey registration
        var hotkeyID: UInt32 {
            switch self {
            case .arrange: return 1
            case .grid: return 2
            case .save: return 3
            }
        }
    }

    // MARK: - Defaults

    static let defaultCombos: [HotkeyAction: KeyCombo] = [
        .arrange: KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey)),
        .grid: KeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey)),
        .save: KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey)),
    ]

    // MARK: - State

    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var callbacks: [HotkeyAction: () -> Void] = [:]
    private var combos: [HotkeyAction: KeyCombo]
    private var sharedHandlerRef: EventHandlerRef?

    init() {
        self.combos = Self.loadCombos()
        installSharedHandler()
    }

    deinit {
        unregisterAll()
        if let handler = sharedHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Shared Event Handler

    /// Install ONE handler for all hotkey events, dispatching by hotkey ID
    private func installSharedHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                // Find matching action by ID
                guard let action = HotkeyAction.allCases.first(where: { $0.hotkeyID == hotKeyID.id }) else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    HotkeyManager.shared.callbacks[action]?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &sharedHandlerRef
        )
    }

    // MARK: - Registration

    func register(action: HotkeyAction, combo: KeyCombo, callback: @escaping () -> Void) {
        unregister(action: action)
        callbacks[action] = callback
        combos[action] = combo

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x534D_544C), // "SMTL"
            id: action.hotkeyID
        )

        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if let hotKeyRef {
            hotKeyRefs[action] = hotKeyRef
        }
    }

    func unregister(action: HotkeyAction) {
        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        callbacks.removeValue(forKey: action)
    }

    func unregisterAll() {
        for action in HotkeyAction.allCases {
            unregister(action: action)
        }
    }

    func combo(for action: HotkeyAction) -> KeyCombo {
        combos[action] ?? Self.defaultCombos[action]!
    }

    /// Known system shortcuts that Carbon won't catch as conflicts
    private static let systemShortcuts: [KeyCombo] = [
        KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)),
        KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey)),
        KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)),
        KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)),
        KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey)),
        KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey)),
        KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey)),
        KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey)),
        KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey)),
        KeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey)),
        KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey)),
        KeyCombo(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)),
        KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey | optionKey)),
    ]

    /// Validate a combo before accepting it.
    func validateCombo(_ combo: KeyCombo, for action: HotkeyAction) -> String? {
        for other in HotkeyAction.allCases where other != action {
            if let existing = combos[other], existing == combo {
                return "Already used for \(other.displayName)"
            }
        }

        if Self.systemShortcuts.contains(combo) {
            return "Reserved by macOS"
        }

        let testID = EventHotKeyID(signature: OSType(0x5453_5400), id: 9999)
        var testRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, testID,
            GetApplicationEventTarget(), 0, &testRef
        )
        if let testRef {
            UnregisterEventHotKey(testRef)
        }
        if status != noErr {
            return "Shortcut may be used by another app"
        }

        return nil
    }

    /// Update combo with validation.
    @discardableResult
    func updateCombo(_ combo: KeyCombo, for action: HotkeyAction) -> String? {
        if let error = validateCombo(combo, for: action) {
            return error
        }
        let callback = callbacks[action]
        combos[action] = combo
        saveCombos()
        if let callback {
            register(action: action, combo: combo, callback: callback)
        }
        return nil
    }

    // MARK: - Singleton

    static let shared = HotkeyManager()

    // MARK: - Persistence

    private static let userDefaultsKey = "SmartTile.hotkeyCombos"

    private static func loadCombos() -> [HotkeyAction: KeyCombo] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let dict = try? JSONDecoder().decode([String: KeyCombo].self, from: data) else {
            return defaultCombos
        }
        var result: [HotkeyAction: KeyCombo] = [:]
        for (key, combo) in dict {
            if let action = HotkeyAction(rawValue: key) {
                result[action] = combo
            }
        }
        for action in HotkeyAction.allCases where result[action] == nil {
            result[action] = defaultCombos[action]
        }
        return result
    }

    private func saveCombos() {
        var dict: [String: KeyCombo] = [:]
        for (action, combo) in combos {
            dict[action.rawValue] = combo
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
