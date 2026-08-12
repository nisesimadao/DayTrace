import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \TimelineEpisode.startDate, order: .reverse) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor, order: .reverse) private var journals: [JournalEntry]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]

    @State private var displayedMonth = Date.now

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var visibleEpisodes: [TimelineEpisode] {
        let suppressed = TimelineVisibility.suppressedEpisodeIDs(from: assertions)
        return episodes.filter { !suppressed.contains($0.id) }
    }

    var body: some View {
        ScrollView {
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
        }
        .navigationTitle("履歴")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(true)
                .accessibilityLabel("検索 — 今後の実装")
            }
        }
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
                        DayCell(date: date, hasMemory: hasMemory(on: date), hasJournal: hasJournal(on: date))
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
    }

    private func hasMemory(on date: Date) -> Bool {
        let interval = DayInterval(containing: date, timeZone: .current)
        return episodes.contains { interval.intersects(start: $0.startDate, end: $0.endDate) }
    }

    private func hasJournal(on date: Date) -> Bool {
        let interval = DayInterval(containing: date, timeZone: .current)
        return journals.contains { $0.dayAnchor >= interval.start && $0.dayAnchor < interval.end }
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

    private var recentAnchors: [Date] {
        let calendar = Calendar.current
        var anchors = Set<Date>()
        for episode in episodes.prefix(120) {
            anchors.insert(calendar.startOfDay(for: episode.startDate))
        }
        for journal in journals.prefix(60) {
            anchors.insert(calendar.startOfDay(for: journal.dayAnchor))
        }
        return anchors.sorted(by: >).prefix(14).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("最近")
                .font(.headline)

            ForEach(recentAnchors, id: \.self) { day in
                RecentDayRow(day: day, episodes: episodes, journals: journals)
            }
        }
    }
}

private struct RecentDayRow: View {
    let day: Date
    let episodes: [TimelineEpisode]
    let journals: [JournalEntry]

    private var interval: DayInterval { DayInterval(containing: day, timeZone: .current) }

    private var stays: [TimelineEpisode] {
        episodes
            .filter { $0.kind == .stay && interval.intersects(start: $0.startDate, end: $0.endDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    private var journal: JournalEntry? {
        journals.first { $0.dayAnchor >= interval.start && $0.dayAnchor < interval.end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(day.formatted(.dateTime.month().day().weekday(.short).locale(Locale(identifier: "ja_JP"))))
                .font(.subheadline.weight(.semibold))

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
