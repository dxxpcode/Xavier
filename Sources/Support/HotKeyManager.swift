import AppKit
import Carbon.HIToolbox

/// Global keyboard shortcut via Carbon RegisterEventHotKey.
/// Option+Space by default; configurable. No accessibility permission required.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredKeyCode: UInt32 = 0
    private var registeredModifiers: UInt32 = 0

    private init() {
        installHandler()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in manager.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func register(keyCode: Int, modifiers: Int) {
        unregister()
        var id = EventHotKeyID(signature: OSType(0x58565231), id: 1) // 'XVR1'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                       GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status == noErr {
            registeredKeyCode = UInt32(keyCode)
            registeredModifiers = UInt32(modifiers)
        } else {
            XavierLog.general.error("Hotkey registration failed: \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Carbon modifier flags for Option (2048), Command (256), Shift (512), Control (4096).
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.control) { m |= controlKey }
        return m
    }

    static func displayString(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    private static func keyName(for keyCode: Int) -> String {
        let names: [Int: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}
