import AppKit
import SwiftUI

/// Root view of the floating assistant panel.
struct ConversationView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var orchestrator: AssistantOrchestrator
    @EnvironmentObject var voice: VoiceSession
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var models: ModelManager

    @State private var inputText = ""
    @State private var attachments: [AttachedFile] = []
    @State private var showHistoryPopover = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            voiceStatusRow
            inputBar
        }
        .background(.windowBackground)
        .frame(minWidth: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("XavierMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
            Text("Xavier")
                .font(.headline)
            Spacer()
            Button { showHistoryPopover.toggle() } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Conversation history")
            .popover(isPresented: $showHistoryPopover) {
                HistoryView()
                    .environmentObject(appState)
                    .environmentObject(orchestrator)
            }
            Button {
                settings.expandWindow.toggle()
                appDelegate?.floatingWindow.setExpanded(settings.expandWindow)
            } label: {
                Image(systemName: settings.expandWindow
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help(settings.expandWindow ? "Collapse" : "Expand")
            Menu {
                Button("New Conversation") { orchestrator.newConversation() }
                Toggle("Exclude from Memory", isOn: Binding(
                    get: { orchestrator.conversation?.excludedFromMemory ?? false },
                    set: { orchestrator.setExcludedFromMemory($0) }
                ))
                Divider()
                Button("Preferences…") { appState.openPreferences() }
                Divider()
                Button("Quit Xavier") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Messages

    private var content: some View {
        Group {
            if orchestrator.messages.isEmpty {
                EmptyStateView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(orchestrator.messages) { message in
                                MessageRowView(message: message,
                                               canRegenerate: message.id == lastAssistantID)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: orchestrator.messages.count) { _, _ in scrollToBottom(proxy) }
                    .onChange(of: orchestrator.messages.last?.content) { _, _ in scrollToBottom(proxy) }
                }
            }
        }
    }

    private var lastAssistantID: String? {
        orchestrator.messages.last(where: { $0.role == .assistant })?.id
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = orchestrator.messages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Voice status

    @ViewBuilder
    private var voiceStatusRow: some View {
        if voice.state != .idle {
            HStack(spacing: 10) {
                WaveformView(state: voice.state, level: voice.audioLevel)
                    .frame(width: 56, height: 20)
                Text(voiceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !voice.liveTranscript.isEmpty {
                    Text(voice.liveTranscript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                if case .speaking = voice.state {
                    Button("Stop") { voice.interruptSpeaking() }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private var voiceLabel: String {
        switch voice.state {
        case .idle: return ""
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .processing: return "Thinking…"
        case .speaking: return "Speaking"
        case .interrupted: return "Interrupted"
        case .error(let m): return m
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 6) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(attachments) { file in
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                Text(file.name).lineLimit(1)
                                Button { attachments.removeAll { $0.id == file.id } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { pickAttachment() } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.borderless)
                .help("Attach a file")

                GrowingTextEditor(text: $inputText, onSubmit: send)

                Button { voice.toggle() } label: {
                    Image(systemName: micIcon)
                        .foregroundStyle(voice.state == .listening ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Voice (⌥M)")

                if orchestrator.isGenerating {
                    Button { orchestrator.cancelGeneration() } label: {
                        Image(systemName: "stop.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop generating")
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                    .help("Send")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var micIcon: String {
        switch voice.state {
        case .listening: return "mic.fill"
        case .speaking: return "speaker.wave.2.fill"
        default: return "mic"
        }
    }

    private func send() {
        guard !orchestrator.isGenerating else { return }
        var text = inputText
        for file in attachments {
            text += "\n\n[Attachment: \(file.name)]\n```\n\(file.preview)\n```"
        }
        inputText = ""
        attachments = []
        appDelegate?.floatingWindow.noteUserActivity()
        orchestrator.send(text: text)
    }

    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                attachments.append(AttachedFile(url: url))
            }
        }
    }

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }
}

struct AttachedFile: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var preview: String {
        guard let data = try? Data(contentsOf: url), data.count < 50_000,
              let text = String(data: data, encoding: .utf8) else {
            return "(binary or large file — path: \(url.path))"
        }
        return text
    }
}
