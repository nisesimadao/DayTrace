import SwiftUI
import WidgetKit

struct DaytraceTodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DaytraceWidgetSnapshot
}

struct DaytraceTodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaytraceTodayWidgetEntry {
        DaytraceTodayWidgetEntry(
            date: .now,
            snapshot: DaytraceWidgetSnapshot(
                day: DaytraceWidgetCivilDay(date: .now, timeZone: .current),
                generatedAt: .now,
                visitCount: 3,
                movementMinutes: 48,
                placeNames: ["学校", "セブン", "自宅"],
                hasJournal: false,
                currentPlaceName: "自宅"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DaytraceTodayWidgetEntry) -> Void) {
        completion(entry(now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaytraceTodayWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = entry(now: now)
        completion(Timeline(entries: [entry], policy: .after(nextDayRefresh(after: now))))
    }

    private func entry(now: Date) -> DaytraceTodayWidgetEntry {
        let today = DaytraceWidgetCivilDay(date: now, timeZone: .current)
        let loaded = DaytraceWidgetSnapshotStore.load()
        let snapshot = loaded?.day == today ? loaded! : .empty(now: now)
        return DaytraceTodayWidgetEntry(date: now, snapshot: snapshot)
    }

    private func nextDayRefresh(after date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(60)
            ?? date.addingTimeInterval(6 * 60 * 60)
    }
}

struct DaytraceTodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DaytraceTodayWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(DaytraceWidgetShared.todayURL)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "circle.dotted")
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text("今日")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.snapshot.visitCount)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .widgetAccentable()
                Text("か所")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if entry.snapshot.movementMinutes > 0 {
                Text("移動 \(movementText(entry.snapshot.movementMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(entry.snapshot.visitCount == 0 ? "まだ記録はありません" : "移動を記録中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Label(
                entry.snapshot.hasJournal ? "日記あり" : "日記はまだ",
                systemImage: entry.snapshot.hasJournal ? "checkmark.circle.fill" : "square.and.pencil"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(entry.snapshot.hasJournal ? .primary : .secondary)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("今日", systemImage: "circle.dotted")
                    .font(.subheadline.weight(.semibold))
                    .widgetAccentable()

                Spacer()

                Text("\(entry.snapshot.visitCount)か所 · 移動 \(movementText(entry.snapshot.movementMinutes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if entry.snapshot.placeNames.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日はまだ記録がありません")
                        .font(.headline)
                    Text("移動すると、訪れた場所の流れがここに表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text(placeFlow(entry.snapshot.placeNames))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .privacySensitive()
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                if let currentPlace = entry.snapshot.currentPlaceName {
                    Label(currentPlace, systemImage: "location.fill")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .privacySensitive()
                } else {
                    Label("今日の記録", systemImage: "location")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Label(
                    entry.snapshot.hasJournal ? "日記あり" : "日記はまだ",
                    systemImage: entry.snapshot.hasJournal ? "checkmark.circle.fill" : "square.and.pencil"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(entry.snapshot.hasJournal ? .primary : .secondary)
            }
        }
    }

    private func movementText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0分" }
        if minutes < 60 { return "\(minutes)分" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)時間" : "\(hours)時間\(remainder)分"
    }

    private func placeFlow(_ names: [String]) -> String {
        let visible = Array(names.prefix(4))
        let suffix = names.count > visible.count ? " → …" : ""
        return visible.joined(separator: " → ") + suffix
    }
}

struct DaytraceTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: DaytraceWidgetShared.widgetKind,
            provider: DaytraceTodayWidgetProvider()
        ) { entry in
            DaytraceTodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日の記録")
        .description("今日訪れた場所、移動時間、日記の状態をひと目で確認できます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DaytraceWidgetBundle: WidgetBundle {
    var body: some Widget {
        DaytraceTodayWidget()
    }
}
