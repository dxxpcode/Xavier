import AppKit
import AVFoundation
import SwiftUI

/// Native preferences, organized per the product spec.
struct PreferencesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralPreferences()
                .tabItem { Label("General", systemImage: "gear") }
            AppearancePreferences()
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            ModelsPreferences()
                .tabItem { Label("AI Models", systemImage: "cpu") }
            VoicePreferences()
                .tabItem { Label("Voice", systemImage: "waveform") }
            MemoryPreferencesView()
                .tabItem { Label("Memory", systemImage: "brain") }
            PrivacyPreferences()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            AdvancedPreferences()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 460)
        .environmentObject(appState.settings)
        .environmentObject(appState.modelManager)
        .environmentObject(appState.memoryEngine)
        .environmentObject(appState.voiceSession)
        .environmentObject(appState.orchestrator)
        .environmentObject(appState)
    }
}

struct GeneralPreferences: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Toggle("Launch Xavier at login", isOn: $settings.launchAtLogin)
            Toggle("Hide when inactive", isOn: $settings.autoHideEnabled)
            if settings.autoHideEnabled {
                HStack {
                    Text("Hide after")
                    Slider(value: $settings.inactivityTimeout, in: 10...300, step: 5)
                    Text("\(Int(settings.inactivityTimeout))s")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            HStack {
                Text("Open Xavier")
                Spacer()
                ShortcutRecorderView(keyCode: $settings.hotkeyKeyCode,
                                     modifiers: $settings.hotkeyModifiers) {
                    HotKeyManager.shared.register(keyCode: settings.hotkeyKeyCode,
                                                  modifiers: settings.hotkeyModifiers)
                }
                Text("(requires a modifier key)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AppearancePreferences: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                Text("System").tag(SettingsStore.Appearance.system)
                Text("Light").tag(SettingsStore.Appearance.light)
                Text("Dark").tag(SettingsStore.Appearance.dark)
            }
            .pickerStyle(.segmented)
            Toggle("Expanded window by default", isOn: $settings.expandWindow)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ModelsPreferences: View {
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var settings: SettingsStore
    @State private var newModelName = ""

    var body: some View {
        Form {
            Section("Runtime") {
                HStack {
                    Text("Ollama")
                    Spacer()
                    statusBadge
                }
                if models.status == .unavailable {
                    Text("Ollama isn't running. Install it from ollama.com, then start it. Xavier checks again automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Check again") {
                        Task { await models.refresh() }
                    }
                }
            }

            Section("Installed models") {
                if models.models.isEmpty {
                    Text(models.status == .available ? "No models installed." : "—")
                        .foregroundStyle(.secondary)
                }
                ForEach(models.models) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.name)
                            if let note = models.hardwareNote(for: model) {
                                Text(note).font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if let p = model.parameterSize {
                            Text(p).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(model.sizeDescription).font(.caption).foregroundStyle(.secondary)
                        if models.selectedModel == model.name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        Button(role: .destructive) {
                            Task { await models.remove(name: model.name) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { models.select(model: model.name) }
                }
            }

            Section("Add a model") {
                HStack {
                    TextField("e.g. llama3.2, qwen3:4b", text: $newModelName)
                        .textFieldStyle(.roundedBorder)
                    Button("Download") {
                        let name = newModelName
                        newModelName = ""
                        Task { await models.pull(name: name) }
                    }
                    .disabled(newModelName.isEmpty || models.pullProgress != nil)
                }
                if let progress = models.pullProgress {
                    ProgressView(value: progress.fraction) {
                        Text(progress.status).font(.caption)
                    }
                }
                if let error = models.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task { await models.refresh() }
        .padding()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch models.status {
        case .unknown, .checking:
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Checking") }
                .foregroundStyle(.secondary)
        case .available:
            Label("Running", systemImage: "circle.fill").foregroundStyle(.green)
        case .unavailable:
            Label("Not running", systemImage: "circle.fill").foregroundStyle(.secondary)
        }
    }
}

struct VoicePreferences: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var voice: VoiceSession

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section("Speech") {
                Toggle("Speak responses aloud", isOn: $settings.speakResponses)
                Picker("Voice", selection: $settings.voiceIdentifier) {
                    Text("System default").tag("")
                    ForEach(voices, id: \.identifier) { v in
                        Text("\(v.name) (\(v.language))").tag(v.identifier)
                    }
                }
                HStack {
                    Text("Speed")
                    Slider(value: $settings.speakingRate, in: 0...1)
                }
            }
            Section("Activation") {
                Toggle("Listen for \"Hey Xavier\"", isOn: $settings.wakeWordEnabled)
                Toggle("Keep listening for follow-ups after a reply", isOn: $settings.voiceFollowUpEnabled)
                if settings.wakeWordEnabled {
                    LabeledContent("Wake word") {
                        Text(voice.wakeWordActive ? "Listening" : "Inactive")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: settings.wakeWordEnabled) { _, _ in voice.applyVoiceSettings() }
            .onChange(of: settings.voiceFollowUpEnabled) { _, _ in voice.applyVoiceSettings() }
            Section("Input") {
                HStack {
                    Text("Microphone permission")
                    Spacer()
                    Text(voice.permissionGranted ? "Granted" : "Not granted")
                        .foregroundStyle(.secondary)
                    Button("Request") {
                        Task { _ = await voice.requestPermissions() }
                    }
                }
                if !voice.onDeviceRecognitionSupported {
                    Text("On-device speech recognition isn't available for this locale. Xavier will not send audio to external servers — voice input will be unavailable.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct MemoryPreferencesView: View {
    @EnvironmentObject var memory: MemoryEngine
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appState: AppState
    @State private var search = ""
    @State private var editing: MemoryItem?
    @State private var editText = ""
    @State private var editCategory: MemoryCategory = .fact
    @State private var confirmDeleteAll = false

    private var displayed: [MemoryItem] {
        search.isEmpty ? memory.memories : memory.search(search)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Automatically remember useful information", isOn: $settings.automaticMemoryEnabled)
                .padding(.horizontal)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search memories", text: $search).textFieldStyle(.plain)
            }
            .padding(8)
            List {
                ForEach(displayed) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        if editing?.id == item.id {
                            TextField("Memory", text: $editText)
                            Picker("Category", selection: $editCategory) {
                                ForEach(MemoryCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            HStack {
                                Button("Save") {
                                    memory.update(id: item.id, content: editText, category: editCategory)
                                    editing = nil
                                }
                                Button("Cancel") { editing = nil }
                            }
                        } else {
                            Text(item.content)
                            HStack {
                                Text(item.category.rawValue)
                                Text("·")
                                Text(item.updatedAt.formatted(date: .abbreviated, time: .omitted))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Edit") {
                            editing = item
                            editText = item.content
                            editCategory = item.category
                        }
                        Button("Delete", role: .destructive) { memory.delete(id: item.id) }
                    }
                }
            }
            .listStyle(.plain)
            HStack {
                Text("\(displayed.count) memories").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Delete All…", role: .destructive) { confirmDeleteAll = true }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .alert("Delete all memories?", isPresented: $confirmDeleteAll) {
            Button("Delete All", role: .destructive) { memory.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every stored memory. Conversations are not affected.")
        }
    }
}

struct PrivacyPreferences: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmDeleteConversations = false

    var body: some View {
        Form {
            Section("Your data") {
                Text("Xavier stores conversations and memories locally on this Mac. AI inference runs locally through your chosen runtime — conversation content is never sent to cloud services.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Data location") {
                    Text("~/Library/Application Support/Xavier")
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            Section("Actions") {
                Button("Export conversations…") { exportData() }
                Button("Delete all conversations…", role: .destructive) { confirmDeleteConversations = true }
            }
            Section("Permissions") {
                Button("Open Privacy & Security settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Delete all conversations?", isPresented: $confirmDeleteConversations) {
            Button("Delete All", role: .destructive) { deleteAllConversations() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every conversation. Stored memories are kept.")
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "xavier-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var export: [[String: Any]] = []
        if let convs = try? appState.conversationStore.listConversations(limit: 10000) {
            for conv in convs {
                let msgs = (try? appState.conversationStore.messages(forConversation: conv.id, limit: 10000)) ?? []
                export.append([
                    "id": conv.id, "title": conv.title,
                    "createdAt": conv.createdAt.timeIntervalSince1970,
                    "messages": msgs.map { ["role": $0.role.rawValue, "content": $0.content, "createdAt": $0.createdAt.timeIntervalSince1970] },
                ])
            }
        }
        let mems = appState.memoryEngine.memories.map {
            ["id": $0.id, "content": $0.content, "category": $0.category.rawValue,
             "createdAt": $0.createdAt.timeIntervalSince1970] as [String: Any]
        }
        let payload: [String: Any] = ["conversations": export, "memories": mems]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? data.write(to: url)
        }
    }

    private func deleteAllConversations() {
        if let convs = try? appState.conversationStore.listConversations(limit: 10000) {
            for c in convs {
                try? appState.conversationStore.deleteConversation(id: c.id)
            }
        }
        appState.orchestrator.newConversation()
    }
}

struct AdvancedPreferences: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var models: ModelManager

    var body: some View {
        Form {
            Section("Runtime") {
                LabeledContent("Ollama endpoint") {
                    TextField("", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                LabeledContent("Runtime status") {
                    Text(String(describing: models.status))
                }
            }
            Section("Diagnostics") {
                LabeledContent("Log file") {
                    Text(XavierLog.logFileURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                Button("Open logs folder") {
                    NSWorkspace.shared.open(XavierLog.logFileURL.deletingLastPathComponent())
                }
            }
            Section("API credentials") {
                Text("If a compatible local endpoint requires an API key, it is stored in the macOS Keychain — never in plain-text files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
