import SwiftUI

/// Siri-style transient response: the last question and Xavier's reply as a
/// compact floating card above the orb. Tap to open the full conversation.
struct AnswerCard: View {
    var exchange: AppState.Exchange
    var onOpenConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !exchange.question.isEmpty {
                Text(exchange.question)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let answer = exchange.answer {
                Text(answer)
                    .font(.callout)
                    .lineLimit(7)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(.secondary).frame(width: 4, height: 4)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onOpenConversation)
        .accessibilityHint("Opens the conversation")
    }
}
