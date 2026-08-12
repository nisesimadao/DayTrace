import Foundation
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \TimelineEpisode.startDate, order: .reverse) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor, order: .reverse) private var journals: [JournalEntry]
    @Query(sort: \MomentNote.timestamp, order: .reverse) private var momentNotes: [MomentNote]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]

    @State private var displayedMonth = Date.now
    @State private var searchText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var visibleEpisodes: [TimelineEpisode] {
        let suppressed = TimelineVisibility.suppressedEpisodeIDs(from: assertions)
        return episodes.filter { !suppressed.contains($0.id) }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            if trimmedSearchText.isEmpty {
                VStack(alignment: .leading, spacing: DS.sectionSpacing) {
                    MonthHeader(displayedMonth: $displayedMonth)
                    MonthGrid(
                        displayedMonth: displayedMonth,
                        episodes: visibleEpisodes,
                        journals: journals,
                        columns: columns
                    )
                    RecentDaysList(episodes: visibleEpisodes, journals: journals)
                }
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 40)
            } else {
                HistorySearchResults(
                    query: trimmedSearchText,
                    episodes: visibleEpisodes,
                    journals: journals,
                    momentNotes: momentNotes
                )
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("履歴")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "場所・日記・メモを検索"
        )
    }
}

private struct MonthHeader: View {
    @Binding var displayedMonth: Date

    var body: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(displayedMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP"))))
                .font(.title2.bold())
                .frame(maxWidth: .infinity)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.top, 12)
    }

    private func shiftMonth(_ amount: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) ?? displayedMonth
    }
}

private struct MonthGrid: View {
    let displayedMonth: Date
    let episodes: [TimelineEpisode]
    let journals: [JournalEntry]
    let columns: [GridItem]

    private var days: [Date?] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { title in
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let day = CalendarDay(containing: date, timeZone: .current)
                        DayCell(
                            date: date,
                            hasMemory: hasMemory(on: day),
                            hasJournal: hasJournal(on: day)
                        )
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
    }

    private func hasMemory(on day: CalendarDay) -> Bool {
        episodes.contains { TimelineDayProjection.episode($0, intersects: day) }
    }

    private func hasJournal(on day: CalendarDay) -> Bool {
        journals.contains { TimelineDayProjection.journal($0, belongsTo: day) }
    }
}

private struct DayCell: View {
    let date: Date
    let hasMemory: Bool
    let hasJournal: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(date.formatted(.dateTime.day()))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.accentColor : .primary)
            HStack(spacing: 3) {
                Circle()
                    .fill(hasMemory ? Color.secondary : .clear)
                    .frame(width: 4, height: 4)
                Circle()
                    .fill(hasJournal ? Color.accentColor : .clear)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .contentShape(Rectangle())
    }
}

private struct RecentDaysList: View {
    let episodes: [TimelineEpisode]
    let journals: [JournalEntry]

    private var recentDays: [CalendarDay] {
        var days = Set<CalendarDay>()
        for episode in episodes.prefix(120) where episode.kind == .stay {
            days.formUnion(TimelineDayProjection.coveredDays(by: episode, limit: 14))
        }
        for journal in journals.prefix(60) {
            days.insert(TimelineDayProjection.day(for: journal))
        }
        return Array(days.sorted(by: >).prefix(14))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("最近")
                .font(.headline)

            ForEach(recentDays, id: \.self) { day in
                RecentDayRow(day: day, episodes: episodes, journals: journals)
            }
        }
    }
}

private struct RecentDayRow: View {
    let day: CalendarDay
    let episodes: [TimelineEpisode]
    let journals: [JournalEntry]

    private var stays: [TimelineEpisode] {
        episodes
            .filter {
                $0.kind == .stay
                    && TimelineDayProjection.episode($0, intersects: day)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private var journal: JournalEntry? {
        journals.first { TimelineDayProjection.journal($0, belongsTo: day) }
    }

    private var displayDate: Date? {
        day.date(in: .current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let displayDate {
                Text(displayDate.formatted(.dateTime.month().day().weekday(.short).locale(Locale(identifier: "ja_JP"))))
                    .font(.subheadline.weight(.semibold))
            }

            if !stays.isEmpty {
                Text(stays.map(\.title).joined(separator: " → "))
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            if let journal, !journal.body.isEmpty {
                Text(journal.body)
                    .font(.body)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct HistorySearchResult: Identifiable {
    let day: CalendarDay
    let episodes: [TimelineEpisode]
    let journal: JournalEntry?
    let notes: [MomentNote]

    var id: CalendarDay { day }
}

private struct HistorySearchResults: View {
    let query: String
    let episodes: [TimelineEpisode]
    let journals: [JournalEntry]
    let momentNotes: [MomentNote]

    private var results: [HistorySearchResult] {
        var episodesByDay: [CalendarDay: [TimelineEpisode]] = [:]
        var journalByDay: [CalendarDay: JournalEntry] = [:]
        var notesByDay: [CalendarDay: [MomentNote]] = [:]
        var allDays = Set<CalendarDay>()

        for episode in episodes where matches(episode) {
            for day in TimelineDayProjection.coveredDays(by: episode, limit: 10_000) {
                episodesByDay[day, default: []].append(episode)
                allDays.insert(day)
            }
        }

        for journal in journals where contains(journal.body) {
            let day = TimelineDayProjection.day(for: journal)
            if journalByDay[day] == nil {
                journalByDay[day] = journal
            }
            allDays.insert(day)
        }

        for note in momentNotes where contains(note.body) {
            let zone = TimelineDayProjection.timeZone(identifier: note.timeZoneIdentifier)
            let day = CalendarDay(containing: note.timestamp, timeZone: zone)
            notesByDay[day, default: []].append(note)
            allDays.insert(day)
        }

        return allDays
            .sorted(by: >)
            .prefix(80)
            .map { day in
                HistorySearchResult(
                    day: day,
                    episodes: (episodesByDay[day] ?? []).sorted { $0.startDate < $1.startDate },
                    journal: journalByDay[day],
                    notes: (notesByDay[day] ?? []).sorted { $0.timestamp < $1.timestamp }
                )
            }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if results.isEmpty {
                ContentUnavailableView {
                    Label("見つかりませんでした", systemImage: "magnifyingglass")
                } description: {
                    Text("場所の名前、日記、メモの言葉を変えて試してください。")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            } else {
                Text("\(results.count)日の記録")
                    .font(.headline)
                    .padding(.top, 12)

                ForEach(results) { result in
                    SearchDayRow(result: result)
                }
            }
        }
    }

    private func matches(_ episode: TimelineEpisode) -> Bool {
        contains(episode.title) || (episode.subtitle.map { contains($0) } ?? false)
    }

    private func contains(_ value: String) -> Bool {
        value.localizedCaseInsensitiveContains(query)
    }
}

private struct SearchDayRow: View {
    let result: HistorySearchResult

    private var displayDate: Date? {
        result.day.date(in: .current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let displayDate {
                Text(displayDate.formatted(.dateTime.year().month().day().weekday(.short).locale(Locale(identifier: "ja_JP"))))
                    .font(.subheadline.weight(.semibold))
            }

            if !result.episodes.isEmpty {
                Text(result.episodes.map(\.title).joined(separator: " → "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let journal = result.journal {
                Text(journal.body)
                    .font(.body)
                    .lineLimit(3)
            }

            ForEach(result.notes.prefix(2), id: \.id) { note in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note.body)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }
}
