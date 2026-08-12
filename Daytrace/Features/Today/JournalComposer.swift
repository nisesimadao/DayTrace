#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
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
                .disabled(!JournalingSuggestionsBridge.isAvailable)
                .accessibilityHint(
                    JournalingSuggestionsBridge.isAvailable
                        ? "システムの振り返り候補を表示します"
                        : "この環境では振り返り候補を利用できません"
                )

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
        .modifier(JournalingSuggestionsBridge(
            isPresented: $isSuggestionPickerPresented,
            onSelection: appendSuggestion
        ))
    }

    private func save() {
        try? JournalEditingService().save(
            day: day,
            body: bodyText,
            existingJournal: existingJournal,
            in: modelContext
        )
        isFocused = false
    }

    @MainActor
    private func appendSuggestion(title: String, date: Date?) {
        let rangeText: String
        if let date {
            rangeText = "（\(TimelineFormatting.clock(date, timeZoneIdentifier: day.timeZone.identifier))ごろ）"
        } else {
            rangeText = ""
        }

        let prefix = bodyText.isEmpty ? "" : "\n"
        bodyText += "\(prefix)\(title)\(rangeText)\n"
        isFocused = true
    }
}

@MainActor
struct JournalEditingService {
    @discardableResult
    func save(
        day: DayInterval,
        body: String,
        existingJournal: JournalEntry?,
        in context: ModelContext,
        now: Date = .now
    ) throws -> JournalEntry? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDay = CalendarDay(containing: day.start, timeZone: day.timeZone)
        let allJournals = try context.fetch(FetchDescriptor<JournalEntry>())
        let matchingJournals = allJournals
            .filter { TimelineDayProjection.day(for: $0) == targetDay }
            .sorted { $0.createdAt < $1.createdAt }

        let preferredJournal = existingJournal.flatMap { existing in
            matchingJournals.first { $0.id == existing.id }
        } ?? matchingJournals.first

        guard !trimmed.isEmpty else {
            for journal in matchingJournals {
                context.delete(journal)
            }
            if !matchingJournals.isEmpty {
                try context.save()
            }
            return nil
        }

        if let journal = preferredJournal {
            journal.body = trimmed
            journal.updatedAt = now
            for duplicate in matchingJournals where duplicate.id != journal.id {
                context.delete(duplicate)
            }
            try context.save()
            return journal
        }

        let journal = JournalEntry(
            dayAnchor: day.start,
            body: trimmed,
            createdAt: now,
            updatedAt: now,
            timeZoneIdentifier: day.timeZone.identifier
        )
        context.insert(journal)
        try context.save()
        return journal
    }
}

private struct JournalingSuggestionsBridge: ViewModifier {
    @Binding var isPresented: Bool
    let onSelection: @MainActor (String, Date?) -> Void

    static var isAvailable: Bool {
#if canImport(JournalingSuggestions)
        true
#else
        false
#endif
    }

    @ViewBuilder
    func body(content: Content) -> some View {
#if canImport(JournalingSuggestions)
        content
            .journalingSuggestionsPicker(isPresented: $isPresented) { suggestion in
                await MainActor.run {
                    onSelection(suggestion.title, suggestion.date?.start)
                }
            }
#else
        content
#endif
    }
}
