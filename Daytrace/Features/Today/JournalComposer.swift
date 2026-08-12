import JournalingSuggestions
import SwiftData
import SwiftUI

struct JournalComposer: View {
    let day: DayInterval
    let existingJournal: JournalEntry?

    @Environment(\.modelContext) private var modelContext
    @State private var bodyText = ""
    @State private var isSuggestionPickerPresented = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .padding(.bottom, 8)

            Text("今日を残す")
                .font(.title2.bold())

            TextEditor(text: $bodyText)
                .focused($isFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: DS.contentCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("今日はどんな日だった？")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                Button {
                    isSuggestionPickerPresented = true
                } label: {
                    Label("思い出す", systemImage: "sparkles")
                }
                .buttonStyle(.daytraceGlass)

                Spacer()

                if existingJournal != nil || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .buttonStyle(.daytraceGlassProminent)
                }
            }
        }
        .onAppear {
            bodyText = existingJournal?.body ?? ""
        }
        .journalingSuggestionsPicker(isPresented: $isSuggestionPickerPresented) { suggestion in
            await appendSuggestion(suggestion)
        }
    }

    private func save() {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingJournal {
            existingJournal.body = trimmed
            existingJournal.updatedAt = .now
        } else if !trimmed.isEmpty {
            modelContext.insert(JournalEntry(
                dayAnchor: day.start,
                body: trimmed,
                timeZoneIdentifier: day.timeZone.identifier
            ))
        }
        try? modelContext.save()
        isFocused = false
    }

    @MainActor
    private func appendSuggestion(_ suggestion: JournalingSuggestion) async {
        let rangeText: String
        if let date = suggestion.date {
            rangeText = "（\(TimelineFormatting.clock(date.start, timeZoneIdentifier: day.timeZone.identifier))ごろ）"
        } else {
            rangeText = ""
        }

        let prefix = bodyText.isEmpty ? "" : "\n"
        bodyText += "\(prefix)\(suggestion.title)\(rangeText)\n"
        isFocused = true
    }
}
