#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import SwiftData
import SwiftUI

struct JournalComposer: View {
    let day: DayInterval
    let existingJournal: JournalEntry?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MomentNote.timestamp) private var momentNotes: [MomentNote]

    @State private var bodyText = ""
    @State private var isSuggestionPickerPresented = false
    @State private var isMomentNotePresented = false
    @FocusState private var isFocused: Bool

    private var targetDay: CalendarDay {
        CalendarDay(containing: day.start, timeZone: day.timeZone)
    }

    private var dayNotes: [MomentNote] {
        momentNotes.filter { note in
            let zone = TimelineDayProjection.timeZone(identifier: note.timeZoneIdentifier)
            return CalendarDay(containing: note.timestamp, timeZone: zone) == targetDay
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .padding(.bottom, 8)

            Text("今日を残す")
                .font(.title2.bold())

            if !dayNotes.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("今日のメモ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(dayNotes) { note in
                        MomentNoteRow(note: note, onDelete: { delete(note) })
                    }
                }
            }

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

                Button {
                    isMomentNotePresented = true
                } label: {
                    Label("今メモ", systemImage: "note.text.badge.plus")
                }
                .buttonStyle(.daytraceGlass)
                .accessibilityHint("今の時刻に短いメモを残します")

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
        .sheet(isPresented: $isMomentNotePresented) {
            MomentNoteComposerSheet()
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

    private func delete(_ note: MomentNote) {
        modelContext.delete(note)
        try? modelContext.save()
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

private struct MomentNoteRow: View {
    let note: MomentNote
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(TimelineFormatting.clock(note.timestamp, timeZoneIdentifier: note.timeZoneIdentifier))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)

            Text(note.body)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("削除", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "削除", onDelete)
    }
}

private struct MomentNoteComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(Date.now.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ja_JP"))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: DS.contentCornerRadius, style: .continuous)
                    )
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("あとで思い出したいこと")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 17)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }

                Spacer()
            }
            .padding(DS.horizontalPadding)
            .navigationTitle("今をメモ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !trimmedText.isEmpty else { return }
        modelContext.insert(MomentNote(
            timestamp: .now,
            body: trimmedText,
            timeZoneIdentifier: TimeZone.current.identifier
        ))
        try? modelContext.save()
        dismiss()
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

        let anchor = try preferredAnchor(
            for: targetDay,
            fallback: day,
            in: context
        )
        let journal = JournalEntry(
            dayAnchor: anchor.start,
            body: trimmed,
            createdAt: now,
            updatedAt: now,
            timeZoneIdentifier: anchor.timeZone.identifier
        )
        context.insert(journal)
        try context.save()
        return journal
    }

    private func preferredAnchor(
        for day: CalendarDay,
        fallback: DayInterval,
        in context: ModelContext
    ) throws -> DayInterval {
        let episodes = try context.fetch(FetchDescriptor<TimelineEpisode>(
            sortBy: [SortDescriptor(\TimelineEpisode.startDate)]
        ))
        if let episode = episodes.first(where: {
            TimelineDayProjection.episode($0, intersects: day)
        }) {
            return projectedInterval(
                for: day,
                timeZoneIdentifier: episode.timeZoneIdentifier,
                fallback: fallback
            )
        }

        let notes = try context.fetch(FetchDescriptor<MomentNote>(
            sortBy: [SortDescriptor(\MomentNote.timestamp)]
        ))
        if let note = notes.first(where: {
            let zone = TimelineDayProjection.timeZone(identifier: $0.timeZoneIdentifier)
            return CalendarDay(containing: $0.timestamp, timeZone: zone) == day
        }) {
            return projectedInterval(
                for: day,
                timeZoneIdentifier: note.timeZoneIdentifier,
                fallback: fallback
            )
        }

        return fallback
    }

    private func projectedInterval(
        for day: CalendarDay,
        timeZoneIdentifier: String,
        fallback: DayInterval
    ) -> DayInterval {
        let zone = TimelineDayProjection.timeZone(identifier: timeZoneIdentifier)
        guard let date = day.date(in: zone) else { return fallback }
        return DayInterval(containing: date, timeZone: zone)
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
