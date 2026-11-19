import AppKit
import SwiftUI

/// A single chat message row.
struct MessageRowView: View {
    let message: ChatMessage
    var canRegenerate: Bool = false
    @EnvironmentObject var orchestrator: AssistantOrchestrator
    @State private var showCopied = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        case .system:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                MarkdownContentView(markdown: message.content)
                    .textSelection(.enabled)
                if message.isComplete && !message.content.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                        } label: {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Copy")
                        if canRegenerate {
                            Button { orchestrator.regenerate() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Regenerate")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Renders Markdown: fenced code blocks get monospace + copy; everything else
/// goes through AttributedString's inline Markdown parser.
struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case .code(let lang, let code):
                    CodeBlockView(language: lang, code: code)
                case .text(let text):
                    if let attributed = try? AttributedString(
                        markdown: text,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(attributed)
                    } else {
                        Text(text)
                    }
                }
            }
        }
    }

    private enum Block: Identifiable {
        case text(String)
        case code(String?, String)
        var id: String {
            switch self {
            case .text(let t): return "t\(t.hashValue)"
            case .code(let l, let c): return "c\(l ?? "")\(c.hashValue)"
            }
        }
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var current = ""
        var inCode = false
        var codeLang: String? = nil
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(codeLang, current.trimmingCharacters(in: .newlines)))
                    current = ""
                    inCode = false
                    codeLang = nil
                } else {
                    if !current.trimmingCharacters(in: .newlines).isEmpty {
                        result.append(.text(current.trimmingCharacters(in: .newlines)))
                    }
                    current = ""
                    inCode = true
                    let lang = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : String(lang)
                }
            } else {
                current += line + "\n"
            }
        }
        if !current.trimmingCharacters(in: .newlines).isEmpty {
            if inCode {
                result.append(.code(codeLang, current.trimmingCharacters(in: .newlines)))
            } else {
                result.append(.text(current.trimmingCharacters(in: .newlines)))
            }
        }
        return result
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image("XavierMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
            Text("How can I help?")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// TextEditor that grows with content and supports Return-to-send
/// (Shift+Return for a newline).
struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.updateHeight(textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            updateHeight(tv)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return false // insert newline
                }
                parent.onSubmit()
                return true
            }
            return false
        }

        func updateHeight(_ tv: NSTextView) {
            tv.layoutManager?.ensureLayout(for: tv.textContainer!)
            let height = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 20
            let clamped = min(max(height + 12, 26), 120)
            tv.enclosingScrollView?.heightAnchor.constraint(equalToConstant: clamped).isActive = true
        }
    }
}
