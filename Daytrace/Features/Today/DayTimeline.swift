import SwiftUI

struct DayTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let episodes: [TimelineEpisode]
    @Binding var selectedEpisodeID: UUID?
    let displayDay: CalendarDay?
    let lastEvidenceAt: Date?
    let currentLocation: CurrentLocationContext?
    let connectsToCurrentLocation: Bool
    let allowsEditing: Bool
    let allowsSuppression: Bool
    let onEdit: (TimelineEpisode) -> Void
    let onSuppress: (TimelineEpisode) -> Void

    init(
        episodes: [TimelineEpisode],
        selectedEpisodeID: Binding<UUID?>,
        displayDay: CalendarDay? = nil,
        lastEvidenceAt: Date?,
        currentLocation: CurrentLocationContext? = nil,
        connectsToCurrentLocation: Bool = false,
        allowsEditing: Bool = true,
        allowsSuppression: Bool = true,
        onEdit: @escaping (TimelineEpisode) -> Void,
        onSuppress: @escaping (TimelineEpisode) -> Void
    ) {
        self.episodes = episodes
        _selectedEpisodeID = selectedEpisodeID
        self.displayDay = displayDay
        self.lastEvidenceAt = lastEvidenceAt
        self.currentLocation = currentLocation
        self.connectsToCurrentLocation = connectsToCurrentLocation
        self.allowsEditing = allowsEditing
        self.allowsSuppression = allowsSuppression
        self.onEdit = onEdit
        self.onSuppress = onSuppress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(orderedEpisodes.enumerated()), id: \.element.id) { index, episode in
                TimelineEpisodeRow(
                    episode: episode,
                    displayDay: displayDay,
                    mapSequenceNumber: mapSequenceNumbers[episode.id],
                    isSelected: selectedEpisodeID == episode.id,
                    drawsTopLine: index > 0,
                    drawsBottomLine: index < orderedEpisodes.count - 1 || connectsToCurrentLocation,
                    lastEvidenceAt: lastEvidenceAt,
                    currentLocation: currentLocation,
                    allowsEditing: allowsEditing,
                    allowsSuppression: allowsSuppression,
                    onSelect: {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            selectedEpisodeID = selectedEpisodeID == episode.id ? nil : episode.id
                        }
                    },
                    onEdit: {
                        guard allowsEditing, episode.kind == .stay || episode.kind == .move else { return }
                        onEdit(episode)
                    },
                    onSuppress: {
                        guard allowsEditing, allowsSuppression, episode.kind == .stay else { return }
                        onSuppress(episode)
                    }
                )
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: selectedEpisodeID)
    }

    private var orderedEpisodes: [TimelineEpisode] {
        episodes.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            let lhsEnd = lhs.endDate ?? .distantFuture
            let rhsEnd = rhs.endDate ?? .distantFuture
            if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var mapSequenceNumbers: [UUID: Int] {
        var nextNumber = 1
        var numbers: [UUID: Int] = [:]

        for episode in orderedEpisodes
        where episode.kind == .stay && episode.latitude != nil && episode.longitude != nil {
            numbers[episode.id] = nextNumber
            nextNumber += 1
        }
        return numbers
    }
}

private struct TimelineEpisodeRow: View {
    let episode: TimelineEpisode
    let displayDay: CalendarDay?
    let mapSequenceNumber: Int?
    let isSelected: Bool
    let drawsTopLine: Bool
    let drawsBottomLine: Bool
    let lastEvidenceAt: Date?
    let currentLocation: CurrentLocationContext?
    let allowsEditing: Bool
    let allowsSuppression: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onSuppress: () -> Void

    private var displayInterval: DateInterval? {
        guard let displayDay else { return nil }
        return TimelineDayProjection.displayInterval(for: episode, on: displayDay)
    }

    private var displayStartDate: Date {
        displayInterval?.start ?? episode.startDate
    }

    private var displayEndDate: Date? {
        guard displayDay != nil else { return episode.endDate }
        return displayInterval?.end
    }

    private var canEdit: Bool {
        allowsEditing && (episode.kind == .stay || episode.kind == .move)
    }

    private var canShowOnMap: Bool {
        episode.kind == .stay && episode.latitude != nil && episode.longitude != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if canShowOnMap {
                Button(action: onSelect) {
                    episodeContent
                        .contentShape(Rectangle())
                }
                .buttonStyle(.daytraceRowLink)
                .accessibilityHint("地図をこの場所へ移動します")
            } else {
                episodeContent
            }

            if canEdit {
                Button("修正", systemImage: "slider.horizontal.3", action: onEdit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.daytraceInk)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
                    .background(Color.daytraceInk.opacity(0.1), in: .capsule)
                    .accessibilityHint("場所と時刻を修正します")
            }
        }
        .contextMenu {
            if canEdit {
                Button("この区間を修正", systemImage: "slider.horizontal.3", action: onEdit)
                if allowsSuppression && episode.kind == .stay {
                    Button("タイムラインから非表示", systemImage: "eye.slash", action: onSuppress)
                }
            }
        }
    }

    private var episodeContent: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(TimelineFormatting.clock(displayStartDate, timeZoneIdentifier: episode.timeZoneIdentifier))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 43, alignment: .trailing)
                .padding(.top, 1)

            TimelineRail(
                episode: episode,
                drawsTopLine: drawsTopLine,
                drawsBottomLine: drawsBottomLine
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(episode.title)
                        .font(episode.kind == .stay ? .body.weight(.semibold) : .subheadline.weight(.medium))

                    if episode.confidence == .low && episode.kind == .stay {
                        Text("?")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                if let subtitle = episode.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let duration = TimelineFormatting.duration(from: displayStartDate, to: displayEndDate) {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if episode.kind == .stay {
                    Text(openEndedStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if canShowOnMap {
                    Label(
                        mapLinkTitle,
                        systemImage: isSelected ? "checkmark.circle.fill" : "map"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.daytraceInk)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, episode.kind == .stay ? DS.timelineRowSpacing : DS.timelineTransitionSpacing)
        }
    }

    private var mapLinkTitle: String {
        guard let mapSequenceNumber else {
            return isSelected ? "地図で表示中" : "地図で見る"
        }
        return isSelected
            ? "地図の\(mapSequenceNumber)番を表示中"
            : "地図の\(mapSequenceNumber)番を見る"
    }

    private var openEndedStatus: String {
        if let currentLocation {
            return CurrentLocationProjection.matches(episode, currentLocation: currentLocation)
                ? "現在"
                : "終了時刻を確認"
        }
        guard let lastEvidenceAt else { return "終了時刻を確認" }
        let age = Date.now.timeIntervalSince(lastEvidenceAt)
        if age <= 20 * 60 {
            return "現在"
        }
        return "最後に確認 \(TimelineFormatting.clock(lastEvidenceAt, timeZoneIdentifier: episode.timeZoneIdentifier))"
    }
}

struct CurrentLocationTimelineRow: View {
    let currentLocation: CurrentLocationContext
    let placeName: String
    let mapSequenceNumber: Int
    let connectsFromPrevious: Bool
    let onRegisterStay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(TimelineFormatting.clock(
                currentLocation.startDate,
                timeZoneIdentifier: currentLocation.timeZoneIdentifier
            ))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 43, alignment: .trailing)
            .padding(.top, 1)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(connectsFromPrevious ? Color.secondary.opacity(0.22) : .clear)
                    .frame(width: DS.timelineLine, height: 8)

                ZStack {
                    Circle()
                        .fill(Color.daytraceInk.opacity(0.16))
                        .frame(width: 22, height: 22)

                    Circle()
                        .fill(Color.daytraceInk)
                        .frame(width: DS.timelineDot, height: DS.timelineDot)
                }

                Rectangle()
                    .fill(.clear)
                    .frame(width: DS.timelineLine)
            }
            .frame(width: DS.timelineRailWidth)
            .frame(minHeight: 82, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(placeName)
                        .font(.body.weight(.semibold))

                    Text("いま")
                        .font(.caption.bold())
                        .foregroundStyle(Color.daytraceInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.1), in: .capsule)
                }

                Text("少なくとも \(TimelineFormatting.clock(currentLocation.startDate, timeZoneIdentifier: currentLocation.timeZoneIdentifier)) から")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("地図の\(mapSequenceNumber)番・滞在判定中", systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.daytraceInk)

                Button(action: onRegisterStay) {
                    Label("ここを滞在として登録", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DS.timelineRowSpacing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "現在地、\(placeName)、少なくとも\(TimelineFormatting.clock(currentLocation.startDate, timeZoneIdentifier: currentLocation.timeZoneIdentifier))から、滞在判定中"
        )
    }
}

struct CurrentLocationTransitionContext: Equatable {
    let kind: EpisodeKind
    let startDate: Date
    let endDate: Date
    let timeZoneIdentifier: String
}

struct CurrentLocationTransitionRow: View {
    let transition: CurrentLocationTransitionContext

    private var title: String {
        transition.kind == .move ? "移動中" : "記録のない区間"
    }

    private var subtitle: String? {
        transition.kind == .gap ? "この間の位置情報を確認できませんでした" : nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(TimelineFormatting.clock(
                transition.startDate,
                timeZoneIdentifier: transition.timeZoneIdentifier
            ))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 43, alignment: .trailing)
            .padding(.top, 1)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: DS.timelineLine, height: 8)

                Image(systemName: transition.kind == .move ? "arrow.down" : "ellipsis")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: DS.timelineDot, height: DS.timelineDot)

                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: DS.timelineLine)
            }
            .frame(width: DS.timelineRailWidth)
            .frame(minHeight: 52, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let duration = TimelineFormatting.duration(from: transition.startDate, to: transition.endDate) {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DS.timelineTransitionSpacing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)、\(TimelineFormatting.duration(from: transition.startDate, to: transition.endDate) ?? "")")
    }
}

private struct TimelineRail: View {
    let episode: TimelineEpisode
    let drawsTopLine: Bool
    let drawsBottomLine: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(drawsTopLine ? Color.secondary.opacity(0.22) : .clear)
                    .frame(width: DS.timelineLine, height: 8)

                symbol

                Rectangle()
                    .fill(drawsBottomLine ? Color.secondary.opacity(0.22) : .clear)
                    .frame(width: DS.timelineLine)
            }
        }
        .frame(width: DS.timelineRailWidth)
        .frame(minHeight: episode.kind == .stay ? 66 : 52, maxHeight: .infinity)
    }

    @ViewBuilder
    private var symbol: some View {
        switch episode.kind {
        case .stay:
            if episode.confidence == .low {
                Circle()
                    .stroke(.secondary, lineWidth: 2)
                    .frame(width: DS.timelineDot, height: DS.timelineDot)
            } else {
                Circle()
                    .fill(Color.daytraceInk)
                    .frame(width: DS.timelineDot, height: DS.timelineDot)
            }
        case .move:
            Image(systemName: "arrow.down")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: DS.timelineDot, height: DS.timelineDot)
        case .gap:
            Image(systemName: "ellipsis")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: DS.timelineDot, height: DS.timelineDot)
        }
    }
}
