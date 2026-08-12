import SwiftUI

struct DayTimeline: View {
    let episodes: [TimelineEpisode]
    @Binding var selectedEpisodeID: UUID?
    let lastEvidenceAt: Date?
    let onEdit: (TimelineEpisode) -> Void
    let onSuppress: (TimelineEpisode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                TimelineEpisodeRow(
                    episode: episode,
                    isSelected: selectedEpisodeID == episode.id,
                    drawsTopLine: index > 0,
                    drawsBottomLine: index < episodes.count - 1,
                    lastEvidenceAt: lastEvidenceAt,
                    onSelect: {
                        withAnimation(.snappy) {
                            selectedEpisodeID = selectedEpisodeID == episode.id ? nil : episode.id
                        }
                    },
                    onEdit: {
                        guard episode.kind == .stay else { return }
                        onEdit(episode)
                    },
                    onSuppress: {
                        guard episode.kind == .stay else { return }
                        onSuppress(episode)
                    }
                )
            }
        }
        .animation(.snappy, value: selectedEpisodeID)
    }
}

private struct TimelineEpisodeRow: View {
    let episode: TimelineEpisode
    let isSelected: Bool
    let drawsTopLine: Bool
    let drawsBottomLine: Bool
    let lastEvidenceAt: Date?
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onSuppress: () -> Void

    var body: some View {
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

                if isSelected && episode.kind == .stay {
                    Label("長押しして修正", systemImage: "hand.tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, episode.kind == .stay ? 30 : 22)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onLongPressGesture(minimumDuration: 0.35, perform: onEdit)
        .contextMenu {
            if episode.kind == .stay {
                Button("場所と時刻を修正", systemImage: "slider.horizontal.3", action: onEdit)
                Button("タイムラインから非表示", systemImage: "eye.slash", action: onSuppress)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "修正", onEdit)
    }

    private var openEndedStatus: String {
        guard let lastEvidenceAt else { return "終了時刻を確認" }
        let age = Date.now.timeIntervalSince(lastEvidenceAt)
        if age <= 20 * 60 {
            return "現在"
        }
        return "最後に確認 \(TimelineFormatting.clock(lastEvidenceAt, timeZoneIdentifier: episode.timeZoneIdentifier))"
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
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: DS.timelineDot, height: DS.timelineDot)
        case .gap:
            Image(systemName: "ellipsis")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: DS.timelineDot, height: DS.timelineDot)
        }
    }
}
