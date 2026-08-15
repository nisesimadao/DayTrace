#if canImport(JournalingSuggestions) && !NO_JOURNALING_SUGGESTIONS
import JournalingSuggestions
#endif
import Foundation
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
    @State private var isSaveErrorPresented = false
    @State private var saveErrorMessage = ""
    @State private var savedBodyText: String?
    @State private var notePendingDeletion: MomentNote?
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

    private var trimmedBodyText: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var persistedBodyText: String {
        savedBodyText ?? existingJournal?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var canSaveJournal: Bool {
        existingJournal != nil || !trimmedBodyText.isEmpty
    }

    private var hasUnsavedJournalChanges: Bool {
        trimmedBodyText != persistedBodyText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日を残す")
                    .font(.title2.bold())

                Text("一文だけでも、あとで一日を連れてきてくれます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !dayNotes.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("今日のメモ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(dayNotes) { note in
                        MomentNoteRow(note: note) {
                            notePendingDeletion = note
                        }
                    }
                }
            }

            TextField(
                "今日の日記",
                text: $bodyText,
                prompt: Text("今日はどんな日だった？").foregroundStyle(.secondary),
                axis: .vertical
            )
                .focused($isFocused)
                .font(.body)
                .lineLimit(4...12)
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: DS.controlCornerRadius))

            HStack(spacing: 10) {
#if canImport(JournalingSuggestions) && !NO_JOURNALING_SUGGESTIONS
                Button {
                    isSuggestionPickerPresented = true
                } label: {
                    Label("思い出す", systemImage: "sparkles")
                }
                .buttonStyle(.daytraceGlass)
                .accessibilityHint("システムの振り返り候補を表示します")
#endif

                Button {
                    isMomentNotePresented = true
                } label: {
                    Label("今メモ", systemImage: "note.text.badge.plus")
                }
                .buttonStyle(.daytraceGlass)
                .accessibilityHint("今の時刻に短いメモを残します")

                Spacer()

                if !hasUnsavedJournalChanges && !persistedBodyText.isEmpty {
                    Label("保存済み", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if canSaveJournal {
                    Button("保存", action: save)
                        .bold()
                        .buttonStyle(.daytraceGlassProminent)
                        .disabled(!hasUnsavedJournalChanges)
                }
            }

            OnThisDaySection()
        }
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
        .onAppear {
            bodyText = existingJournal?.body ?? ""
            savedBodyText = existingJournal?.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .sheet(isPresented: $isMomentNotePresented) {
            MomentNoteComposerSheet()
        }
        .confirmationDialog(
            "今メモを削除しますか？",
            isPresented: Binding(
                get: { notePendingDeletion != nil },
                set: { if !$0 { notePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                guard let note = notePendingDeletion else { return }
                notePendingDeletion = nil
                delete(note)
            }
            Button("キャンセル", role: .cancel) {
                notePendingDeletion = nil
            }
        }
        .alert("日記を保存できません", isPresented: $isSaveErrorPresented) { } message: {
            Text(saveErrorMessage)
        }
#if canImport(JournalingSuggestions) && !NO_JOURNALING_SUGGESTIONS
        .modifier(JournalingSuggestionsBridge(
            isPresented: $isSuggestionPickerPresented,
            onSelection: appendSuggestion
        ))
#endif
    }

    private func save() {
        do {
            try JournalEditingService().save(
                day: day,
                body: bodyText,
                existingJournal: existingJournal,
                in: modelContext
            )
            savedBodyText = trimmedBodyText
            isFocused = false
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaveErrorPresented = true
        }
    }

    private func delete(_ note: MomentNote) {
        do {
            modelContext.delete(note)
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaveErrorPresented = true
        }
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
    @State private var isSaveErrorPresented = false
    @State private var saveErrorMessage = ""
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

                TextField(
                    "今メモ",
                    text: $text,
                    prompt: Text("あとで思い出したいこと").foregroundStyle(.secondary),
                    axis: .vertical
                )
                    .focused($isFocused)
                    .font(.body)
                    .lineLimit(4...10)
                    .padding(14)
                    .background(
                        Color(.secondarySystemBackground),
                        in: .rect(cornerRadius: DS.contentCornerRadius)
                    )

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
                        .bold()
                        .disabled(trimmedText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { isFocused = true }
        .alert("メモを保存できません", isPresented: $isSaveErrorPresented) { } message: {
            Text(saveErrorMessage)
        }
    }

    private func save() {
        guard !trimmedText.isEmpty else { return }
        do {
            modelContext.insert(MomentNote(
                timestamp: .now,
                body: trimmedText,
                timeZoneIdentifier: TimeZone.current.identifier
            ))
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaveErrorPresented = true
        }
    }
}

private struct OnThisDayMemory {
    let day: CalendarDay
    let yearsAgo: Int
    let routeText: String?
    let journalExcerpt: String?
}

private struct OnThisDaySection: View {
    @Query(sort: \TimelineEpisode.startDate) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor) private var journals: [JournalEntry]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]

    private var today: CalendarDay {
        CalendarDay(containing: .now, timeZone: .current)
    }

    private var suppressedEpisodeIDs: Set<UUID> {
        TimelineVisibility.suppressedEpisodeIDs(from: assertions)
    }

    private var privatePlaceIDs: Set<UUID> {
        Set(places.filter { $0.isPrivate }.map { $0.id })
    }

    private var visibleStays: [TimelineEpisode] {
        episodes.filter { episode in
            episode.kind == .stay && !suppressedEpisodeIDs.contains(episode.id)
        }
    }

    private var memory: OnThisDayMemory? {
        var candidateDays = Set<CalendarDay>()

        for stay in visibleStays {
            candidateDays.formUnion(TimelineDayProjection.coveredDays(by: stay, limit: 366))
        }
        for journal in journals {
            candidateDays.insert(TimelineDayProjection.day(for: journal))
        }

        let matchingDays = candidateDays.filter { candidate in
            candidate.year < today.year
                && candidate.month == today.month
                && candidate.day == today.day
        }
        guard let matchingDay = matchingDays.max(by: { lhs, rhs in
            lhs.year < rhs.year
        }) else {
            return nil
        }

        let stays = visibleStays
            .filter { TimelineDayProjection.episode($0, intersects: matchingDay) }
            .sorted { $0.startDate < $1.startDate }
        let journal = journals.first { TimelineDayProjection.journal($0, belongsTo: matchingDay) }

        let route = routeText(for: stays)
        let trimmedJournal = journal?.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = (trimmedJournal?.isEmpty == false) ? trimmedJournal : nil
        guard route != nil || excerpt != nil else { return nil }

        return OnThisDayMemory(
            day: matchingDay,
            yearsAgo: today.year - matchingDay.year,
            routeText: route,
            journalExcerpt: excerpt
        )
    }

    @ViewBuilder
    var body: some View {
        if let memory {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                Text("\(memory.yearsAgo)年前の今日")
                    .font(.title3.bold())

                NavigationLink(value: memory.day) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(memory.day.year)年\(memory.day.month)月\(memory.day.day)日")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            if let routeText = memory.routeText {
                                Text(routeText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if let excerpt = memory.journalExcerpt {
                                Text(excerpt)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: DS.contentCornerRadius, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(memory.yearsAgo)年前の今日、\(memory.day.year)年\(memory.day.month)月\(memory.day.day)日の記録を開く")
            }
        }
    }

    private func routeText(for stays: [TimelineEpisode]) -> String? {
        var names: [String] = []
        for stay in stays {
            let name: String
            if let placeID = stay.placeID, privatePlaceIDs.contains(placeID) {
                name = "非公開の場所"
            } else {
                name = stay.title
            }

            if names.last != name {
                names.append(name)
            }
        }

        guard !names.isEmpty else { return nil }
        let visible = Array(names.prefix(4))
        let suffix = names.count > visible.count ? " → …" : ""
        return visible.joined(separator: " → ") + suffix
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
            if UserDefaults.standard.bool(forKey: ReviewReminderService.enabledKey) {
                Task { @MainActor in
                    try? await ReviewReminderService.refresh(in: context)
                }
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
            ReviewReminderService.cancel(for: targetDay)
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
        ReviewReminderService.cancel(for: targetDay)
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

#if canImport(JournalingSuggestions) && !NO_JOURNALING_SUGGESTIONS
private struct JournalingSuggestionsBridge: ViewModifier {
    @Binding var isPresented: Bool
    let onSelection: @MainActor (String, Date?) -> Void

    func body(content: Content) -> some View {
        content
            .journalingSuggestionsPicker(isPresented: $isPresented) { suggestion in
                await MainActor.run {
                    onSelection(suggestion.title, suggestion.date?.start)
                }
            }
    }
}
#endif
