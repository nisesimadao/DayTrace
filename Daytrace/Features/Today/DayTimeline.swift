import SwiftUI

struct DayTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let episodes: [TimelineEpisode]
    @Binding var selectedEpisodeID: UUID?
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
            ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                TimelineEpisodeRow(
                    episode: episode,
                    mapSequenceNumber: mapSequenceNumbers[episode.id],
                    isSelected: selectedEpisodeID == episode.id,
                    drawsTopLine: index > 0,
                    drawsBottomLine: index < episodes.count - 1 || connectsToCurrentLocation,
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
                        guard allowsEditing, episode.kind == .stay else { return }
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

    private var mapSequenceNumbers: [UUID: Int] {
        var nextNumber = 1
        var numbers: [UUID: Int] = [:]

        for episode in episodes
        where episode.kind == .stay && episode.latitude != nil && episode.longitude != nil {
            numbers[episode.id] = nextNumber
            nextNumber += 1
        }
        return numbers
    }
}

private struct TimelineEpisodeRow: View {
    let episode: TimelineEpisode
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

    private var canEdit: Bool {
        allowsEditing && episode.kind == .stay
    }

    private var canShowOnMap: Bool {
        episode.kind == .stay && episode.latitude != nil && episode.longitude != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
                    .foregroundStyle(.tint)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 9)
                    .background(Color.accentColor.opacity(0.1), in: .capsule)
                    .accessibilityHint("場所と時刻を修正します")
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear, in: .rect(cornerRadius: 14))
        .contextMenu {
            if canEdit {
                Button("場所と時刻を修正", systemImage: "slider.horizontal.3", action: onEdit)
                if allowsSuppression {
                    Button("タイムラインから非表示", systemImage: "eye.slash", action: onSuppress)
                }
            }
        }
    }

    private var episodeContent: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(TimelineFormatting.clock(episode.startDate, timeZoneIdentifier: episode.timeZoneIdentifier))
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

                if let duration = TimelineFormatting.duration(from: episode.startDate, to: episode.endDate) {
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
                        .foregroundStyle(.tint)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, episode.kind == .stay ? 30 : 22)
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
        HStack(alignment: .top, spacing: 14) {
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
                        .fill(.tint.opacity(0.16))
                        .frame(width: 22, height: 22)

                    Circle()
                        .fill(.tint)
                        .frame(width: DS.timelineDot, height: DS.timelineDot)
                }

                Rectangle()
                    .fill(.clear)
                    .frame(width: DS.timelineLine)
            }
            .frame(width: 20)
            .frame(minHeight: 82)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(placeName)
                        .font(.body.weight(.semibold))

                    Text("いま")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.1), in: .capsule)
                }

                Text("少なくとも \(TimelineFormatting.clock(currentLocation.startDate, timeZoneIdentifier: currentLocation.timeZoneIdentifier)) から")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("地図の\(mapSequenceNumber)番・滞在判定中", systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)

                Button(action: onRegisterStay) {
                    Label("ここを滞在として登録", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 26)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "現在地、\(placeName)、少なくとも\(TimelineFormatting.clock(currentLocation.startDate, timeZoneIdentifier: currentLocation.timeZoneIdentifier))から、滞在判定中"
        )
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
        .frame(width: 20)
        .frame(minHeight: episode.kind == .stay ? 66 : 52)
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
                    .fill(.tint)
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
