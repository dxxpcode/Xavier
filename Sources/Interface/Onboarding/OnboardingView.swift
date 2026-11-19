import AppKit
import SwiftUI

/// First-launch onboarding inside a regular window: welcome, local AI, voice,
/// memory, shortcut, done. No account required.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var voice: VoiceSession
    @EnvironmentObject var settings: SettingsStore

    @State private var step = 0

    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 20)

            Spacer()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: aiStep
                case 2: voiceStep
                case 3: memoryStep
                case 4: shortcutStep
                default: doneStep
                }
            }
            .frame(maxWidth: 400)

            Spacer()

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 5 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start using Xavier") { finish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 440)
        .task { await models.refresh() }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image("XavierMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
            Text("Welcome to Xavier")
                .font(.title)
            Text("A personal assistant that lives in your Mac. Open it anywhere with a keyboard shortcut, talk or type, and it remembers what matters — all on your machine.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var aiStep: some View {
        VStack(spacing: 16) {
            Text("Local AI").font(.title2)
            Text("Xavier thinks entirely on your Mac. It uses a local model runtime — your conversations never leave this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                switch models.status {
                case .available:
                    Label("Ollama is running", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .unavailable:
                    Label("Ollama not detected", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                default:
                    ProgressView().controlSize(.small)
                }
            }
            if models.status == .unavailable {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To get started:")
                        .font(.headline)
                    Text("1. Install Ollama from ollama.com")
                    Text("2. Run: ollama pull llama3.2")
                    Text("3. Come back here — Xavier picks it up automatically.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                Button("Check again") { Task { await models.refresh() } }
            } else if !models.models.isEmpty {
                Picker("Default model", selection: Binding(
                    get: { models.selectedModel },
                    set: { models.select(model: $0) }
                )) {
                    ForEach(models.models) { Text($0.name).tag($0.name) }
                }
                .frame(maxWidth: 280)
            }
        }
    }

    private var voiceStep: some View {
        VStack(spacing: 16) {
            Text("Voice").font(.title2)
            Text("Press the microphone button or ⌥M in the panel to talk. Speech is recognized on-device — audio never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Allow microphone & speech") {
                    Task { _ = await voice.requestPermissions() }
                }
                if voice.permissionGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            if !voice.onDeviceRecognitionSupported {
                Text("On-device recognition isn't available for this locale — voice input will stay off rather than send audio out.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var memoryStep: some View {
        VStack(spacing: 16) {
            Text("Memory").font(.title2)
            Text("Xavier remembers useful things across conversations — your preferences, projects, and instructions. You can review, edit, or delete anything it keeps in Preferences → Memory.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Toggle("Automatically remember useful information", isOn: $settings.automaticMemoryEnabled)
        }
    }

    private var shortcutStep: some View {
        VStack(spacing: 16) {
            Text("Keyboard shortcut").font(.title2)
            Text("Open Xavier from anywhere.")
                .foregroundStyle(.secondary)
            ShortcutRecorderView(keyCode: $settings.hotkeyKeyCode,
                                 modifiers: $settings.hotkeyModifiers) {
                HotKeyManager.shared.register(keyCode: settings.hotkeyKeyCode,
                                              modifiers: settings.hotkeyModifiers)
            }
            .font(.title3)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Text("Tip: hold a modifier (⌥ ⌘ ⇧ ⌃) plus a key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image("XavierMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
            Text("You're set").font(.title2)
            Text("Press \(HotKeyManager.displayString(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)) anytime to open Xavier.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }
}
