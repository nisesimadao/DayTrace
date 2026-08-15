import Foundation
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TimelineEpisode.startDate, order: .reverse) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor, order: .reverse) private var journals: [JournalEntry]
    @Query(sort: \MomentNote.timestamp, order: .reverse) private var momentNotes: [MomentNote]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]

    @State private var displayedMonth = Date.now
    @State private var searchText = ""

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
                    HistoryPlacesLink()
                    HistoryCalendarCard(
                        displayedMonth: displayedMonth,
                        setDisplayedMonth: { displayedMonth = $0 },
                        episodes: visibleEpisodes,
                        journals: journals
                    )
                    RecentDaysList(episodes: visibleEpisodes, journals: journals)
                }
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HistorySearchResults(
                    query: trimmedSearchText,
                    episodes: visibleEpisodes,
                    journals: journals,
                    momentNotes: momentNotes
                )
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "場所・日記・メモを検索"
        )
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: trimmedSearchText.isEmpty)
    }
}

private struct HistoryPlacesLink: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(value: HistoryDestination.places) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        mapIcon

                        Text("場所から振り返る")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("覚えた場所を地図で見て、訪れた日を開く")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Label("場所の地図を開く", systemImage: "arrow.right")
                            .font(.headline)
                            .foregroundStyle(Color.daytraceInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.daytraceInk.opacity(0.12), in: .capsule)
                    }
                } else {
                    HStack(spacing: 14) {
                        mapIcon

                        VStack(alignment: .leading, spacing: 3) {
                            Text("場所から振り返る")
                                .font(.headline)
                            Text("覚えた場所を地図で見て、訪れた日を開く")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 4)

                        Text("開く")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.daytraceInk)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color.daytraceInk.opacity(0.12), in: .capsule)
                    }
                }
            }
            .padding(DS.cardPadding)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.daytraceRowLink)
        .hoverEffect(.highlight)
        .padding(.top, 8)
        .accessibilityHint("覚えた場所の地図を開きます")
    }

    private var mapIcon: some View {
        Image(systemName: "map.fill")
            .font(.title2)
            .foregroundStyle(Color.daytraceInk)
            .frame(width: 44, height: 44)
            .background(Color.daytraceInk.opacity(0.12), in: .circle)
    }
}

private struct HistoryCalendarCard: View {
    let displayedMonth: Date
    let setDisplayedMonth: (Date) -> Void
    let episodes: [TimelineEpisode]
    let journals: [JournalEntry]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("日付から振り返る")
                    .font(.title3.bold())
                Text("日付をタップすると、その日の記録と日記を開きます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            MonthHeader(
                displayedMonth: displayedMonth,
                setDisplayedMonth: setDisplayedMonth
            )
            MonthGrid(
                displayedMonth: displayedMonth,
                episodes: episodes,
                journals: journals,
                columns: columns
            )

            HStack(spacing: 16) {
                Label("日記あり", systemImage: "book.closed.fill")
                Label("場所あり", systemImage: "location.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
        .padding(.top, 8)
    }
}

private struct MonthHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let displayedMonth: Date
    let setDisplayedMonth: (Date) -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                controls
            }
        } else {
            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                monthTitle

                HStack(spacing: 12) {
                    previousMonthButton
                        .frame(maxWidth: .infinity)
                    nextMonthButton
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack {
                previousMonthButton
                monthTitle
                    .frame(maxWidth: .infinity)
                nextMonthButton
            }
        }
    }

    private var monthTitle: some View {
        Text(displayedMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP"))))
            .font(.title2.bold())
            .multilineTextAlignment(.center)
            .contentTransition(.numericText())
    }

    private var previousMonthButton: some View {
        Button("前月", systemImage: "chevron.left") { shiftMonth(-1) }
            .font(.caption.weight(.semibold))
            .buttonStyle(.daytraceGlass)
    }

    private var nextMonthButton: some View {
        Button("次月", systemImage: "chevron.right") { shiftMonth(1) }
            .font(.caption.weight(.semibold))
            .buttonStyle(.daytraceGlass)
    }

    private func shiftMonth(_ amount: Int) {
        let shifted = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) ?? displayedMonth
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            setDisplayedMonth(shifted)
        }
    }
}

private struct MonthGrid: View {
    let displayedMonth: Date
    let episodes: [TimelineEpisode]
    let journals: [JournalEntry]
    let columns: [GridItem]

    private var today: CalendarDay {
        CalendarDay(containing: .now, timeZone: .current)
    }

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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                // EnumeratedSequence becomes a RandomAccessCollection only on iOS 26.
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let day = CalendarDay(containing: date, timeZone: .current)
                        let cell = DayCell(
                            date: date,
                            hasMemory: hasMemory(on: day),
                            hasJournal: hasJournal(on: day)
                        )

                        if day <= today {
                            NavigationLink(value: day) { cell }
                                .buttonStyle(.plain)
                                .hoverEffect(.highlight)
                        } else {
                            cell.opacity(0.35)
                        }
                    } else {
                        Color.clear.frame(height: 44)
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
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(hasJournal ? Color.daytraceInk : .primary)
            Image(systemName: hasJournal ? "book.closed.fill" : hasMemory ? "location.fill" : "circle.fill")
                .font(.system(size: hasJournal || hasMemory ? 8 : 3, weight: .semibold))
                .foregroundStyle(hasJournal ? Color.daytraceInk : hasMemory ? Color.secondary : Color.clear)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            hasJournal
                ? Color.daytraceInk.opacity(0.14)
                : hasMemory
                    ? Color(.secondarySystemFill)
                    : Color(.tertiarySystemFill).opacity(0.5),
            in: .rect(cornerRadius: 12)
        )
        .overlay {
            if Calendar.current.isDateInToday(date) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.daytraceInk, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [date.formatted(.dateTime.month().day().locale(Locale(identifier: "ja_JP")))]
        if hasMemory { parts.append("位置の手がかりあり") }
        if hasJournal { parts.append("日記あり") }
        parts.append("開く")
        return parts.joined(separator: "、")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近の記録")
                    .font(.title3.bold())
                Spacer()
                Text("\(recentDays.count)日")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if recentDays.isEmpty {
                ContentUnavailableView {
                    Label("まだ記録がありません", systemImage: "book.closed")
                } description: {
                    Text("日記や場所の手がかりが、ここに日付順で並びます。")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(recentDays.enumerated()), id: \.element) { index, day in
                        NavigationLink(value: day) {
                            RecentDayRow(day: day, episodes: episodes, journals: journals)
                        }
                        .buttonStyle(.daytraceRowLink)
                        .hoverEffect(.highlight)

                        if index < recentDays.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
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
        HStack(spacing: 14) {
            if let displayDate {
                VStack(spacing: 1) {
                    Text(displayDate.formatted(.dateTime.day()))
                        .font(.title3.bold().monospacedDigit())
                    Text(displayDate.formatted(.dateTime.month(.abbreviated).weekday(.short).locale(Locale(identifier: "ja_JP"))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 48)
            }

            VStack(alignment: .leading, spacing: 5) {
                if let journal, !journal.body.isEmpty {
                    Text(journal.body)
                        .font(.body)
                        .lineLimit(2)
                } else {
                    Text(stays.isEmpty ? "一日の記録" : stays.first?.title ?? "一日の記録")
                        .font(.body.bold())
                        .lineLimit(1)
                }

                if !stays.isEmpty {
                    Label(stays.map(\.title).joined(separator: " → "), systemImage: "location")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Text("開く")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.daytraceInk)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.daytraceInk.opacity(0.12), in: .capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
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
                    NavigationLink(value: result.day) {
                        SearchDayRow(result: result)
                    }
                    .buttonStyle(.daytraceRowLink)
                    .hoverEffect(.highlight)
                }
            }
        }
    }

    private func matches(_ episode: TimelineEpisode) -> Bool {
        contains(episode.title) || (episode.subtitle.map { contains($0) } ?? false)
    }

    private func contains(_ value: String) -> Bool {
        value.localizedStandardContains(query)
    }
}

private struct SearchDayRow: View {
    let result: HistorySearchResult

    private var displayDate: Date? {
        result.day.date(in: .current)
    }

    var body: some View {
        HStack(spacing: 12) {
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

            Spacer(minLength: 4)

            Text("開く")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.daytraceInk)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.daytraceInk.opacity(0.12), in: .capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: DS.contentCornerRadius))
        .contentShape(Rectangle())
    }
}

struct HistoricalDayDetailView: View {
    let day: CalendarDay

    @Query(sort: \TimelineEpisode.startDate) private var episodes: [TimelineEpisode]
    @Query(sort: \JournalEntry.dayAnchor) private var journals: [JournalEntry]
    @Query(sort: \MomentNote.timestamp) private var momentNotes: [MomentNote]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]
    @Query(sort: \LocationEvidence.timestamp) private var locationEvidence: [LocationEvidence]

    @State private var selectedEpisodeID: UUID?
    @State private var isMapExpanded = false
    @State private var stayEditSelection: HistoricalStayEditSelection?

    private var suppressedEpisodeIDs: Set<UUID> {
        TimelineVisibility.suppressedEpisodeIDs(from: assertions)
    }

    private var dayEpisodes: [TimelineEpisode] {
        episodes
            .filter {
                !suppressedEpisodeIDs.contains($0.id)
                    && TimelineDayProjection.episode($0, intersects: day)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private var journal: JournalEntry? {
        journals.first { TimelineDayProjection.journal($0, belongsTo: day) }
    }

    private var dayNotes: [MomentNote] {
        momentNotes.filter { note in
            let zone = TimelineDayProjection.timeZone(identifier: note.timeZoneIdentifier)
            return CalendarDay(containing: note.timestamp, timeZone: zone) == day
        }
    }

    private var timeZone: TimeZone {
        if let journal {
            return TimelineDayProjection.timeZone(identifier: journal.timeZoneIdentifier)
        }
        if let stay = dayEpisodes.first(where: { $0.kind == .stay }) {
            return TimelineDayProjection.timeZone(identifier: stay.timeZoneIdentifier)
        }
        if let episode = dayEpisodes.first {
            return TimelineDayProjection.timeZone(identifier: episode.timeZoneIdentifier)
        }
        return .current
    }

    private var interval: DayInterval {
        DayInterval(containing: day.date(in: timeZone) ?? .now, timeZone: timeZone)
    }

    private var displayDate: Date? {
        day.date(in: .current)
    }

    private var hasLocatableStay: Bool {
        dayEpisodes.contains { $0.kind == .stay && $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sectionSpacing) {
                if let displayDate {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayDate.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "ja_JP"))))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(displayDate.formatted(.dateTime.year().month(.wide).day().locale(Locale(identifier: "ja_JP"))))
                            .font(.title.bold())
                            .fontDesign(.rounded)
                    }
                    .padding(.top, 8)
                }

                if hasLocatableStay {
                    DayMap(
                        episodes: dayEpisodes,
                        routeLocations: dayRouteLocations,
                        selectedEpisodeID: $selectedEpisodeID,
                        onExpand: showExpandedMap
                    )
                }

                if dayEpisodes.isEmpty {
                    ContentUnavailableView {
                        Label("位置の記録はありません", systemImage: "location.slash")
                    } description: {
                        Text("この日も日記を残せます。")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    DayTimeline(
                        episodes: dayEpisodes,
                        selectedEpisodeID: $selectedEpisodeID,
                        lastEvidenceAt: nil,
                        allowsEditing: true,
                        allowsSuppression: false,
                        onEdit: { episode in
                            stayEditSelection = HistoricalStayEditSelection(episode: episode)
                        },
                        onSuppress: { _ in }
                    )
                }

                HistoricalJournalEditor(
                    day: interval,
                    existingJournal: journal,
                    notes: dayNotes
                )
            }
            .padding(.horizontal, DS.horizontalPadding)
            .padding(.bottom, 40)
        }
        .navigationTitle("この日")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $stayEditSelection) { selection in
            StayEditorSheet(
                episode: selection.episode,
                rebuildHistoricalTransitions: true
            )
        }
        .fullScreenCover(isPresented: $isMapExpanded) {
            ExpandedDayMapView(
                title: "この日の足あと",
                episodes: dayEpisodes,
                routeLocations: dayRouteLocations,
                currentLocation: nil,
                selectedEpisodeID: $selectedEpisodeID
            )
        }
    }

    private func showExpandedMap() {
        isMapExpanded = true
    }

    private var dayRouteLocations: [LocationEvidence] {
        locationEvidence.filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }
    }
}

private struct HistoricalStayEditSelection: Identifiable {
    let episode: TimelineEpisode
    var id: UUID { episode.id }
}

private struct HistoricalJournalEditor: View {
    let day: DayInterval
    let existingJournal: JournalEntry?
    let notes: [MomentNote]

    @Environment(\.modelContext) private var modelContext
    @State private var bodyText = ""
    @State private var isSaveErrorPresented = false
    @State private var saveErrorMessage = ""
    @State private var savedBodyText: String?
    @State private var notePendingDeletion: MomentNote?
    @FocusState private var isFocused: Bool

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
            Divider()
                .padding(.bottom, 8)

            Text("この日を残す")
                .font(.title2.bold())

            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("この日のメモ")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(notes) { note in
                        HistoricalMomentNoteRow(note: note) {
                            notePendingDeletion = note
                        }
                    }
                }
            }

            TextField(
                "この日の日記",
                text: $bodyText,
                prompt: Text("この日はどんな日だった？").foregroundStyle(.secondary),
                axis: .vertical
            )
                .focused($isFocused)
                .font(.body)
                .lineLimit(4...12)
                .padding(14)
                .background(
                    Color(.secondarySystemBackground),
                    in: .rect(cornerRadius: DS.contentCornerRadius)
                )

            HStack {
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
        }
        .onAppear {
            bodyText = existingJournal?.body ?? ""
            savedBodyText = existingJournal?.body.trimmingCharacters(in: .whitespacesAndNewlines)
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
}

private struct HistoricalMomentNoteRow: View {
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
