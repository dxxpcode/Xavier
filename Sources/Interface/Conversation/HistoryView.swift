import SwiftUI

/// Conversation history popover: search, restore, rename, delete.
struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var orchestrator: AssistantOrchestrator

    @State private var conversations: [Conversation] = []
    @State private var search = ""
    @State private var editingID: String?
    @State private var editTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search conversations", text: $search)
                    .textFieldStyle(.plain)
                    .onChange(of: search) { _, _ in reload() }
            }
            .padding(8)

            Divider()

            List {
                ForEach(conversations) { conv in
                    HStack {
                        if editingID == conv.id {
                            TextField("Title", text: $editTitle, onCommit: {
                                try? appState.conversationStore.renameConversation(id: conv.id, title: editTitle)
                                editingID = nil
                                reload()
                            })
                            .textFieldStyle(.plain)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conv.title).lineLimit(1)
                                Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                orchestrator.load(conversation: conv)
                            }
                        }
                        Spacer()
                        Menu {
                            Button("Rename") {
                                editingID = conv.id
                                editTitle = conv.title
                            }
                            Button("Delete", role: .destructive) {
                                orchestrator.deleteConversation(id: conv.id)
                                reload()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.secondary)
                        }
                        .menuIndicator(.hidden)
                        .menuStyle(.borderlessButton)
                        .frame(width: 20)
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 300, height: 360)
        .onAppear(perform: reload)
    }

    private func reload() {
        do {
            conversations = search.isEmpty
                ? try appState.conversationStore.listConversations()
                : try appState.conversationStore.searchConversations(search)
        } catch {
            conversations = []
        }
    }
}
