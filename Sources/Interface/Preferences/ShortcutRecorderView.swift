import AppKit
import SwiftUI

/// Captures a key combination (modifier + key) for the global shortcut.
struct ShortcutRecorderView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : HotKeyManager.displayString(keyCode: keyCode, modifiers: modifiers)) {
            startRecording()
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .intersection([.option, .command, .shift, .control])
            if event.keyCode == 53 { // Escape cancels
                Task { @MainActor in stopRecording() }
                return nil
            }
            guard !mods.isEmpty else { return event }
            Task { @MainActor in
                keyCode = Int(event.keyCode)
                modifiers = HotKeyManager.carbonModifiers(from: mods)
                stopRecording()
                onChange()
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
