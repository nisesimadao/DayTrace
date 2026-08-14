import MapKit
import SwiftData
import SwiftUI

enum HistoryDestination: Hashable {
    case places
}

struct HistoryRootView: View {
    var body: some View {
        HistoryView()
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: HistoryDestination.places) {
                        Label("場所の記憶", systemImage: "map")
                    }
                    .accessibilityHint("覚えた場所の地図を開きます")
                }
            }
            .navigationDestination(for: HistoryDestination.self) { destination in
                switch destination {
                case .places:
                    HistoryPlacesMap()
                        .navigationTitle("場所の記憶")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .navigationDestination(for: CalendarDay.self) { day in
                HistoricalDayDetailView(day: day)
            }
    }
}

struct HistoryPlacesMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query(sort: \TimelineEpisode.startDate, order: .reverse) private var episodes: [TimelineEpisode]
    @Query(sort: \UserAssertion.createdAt) private var assertions: [UserAssertion]

    @State private var selectedPlaceID: UUID?
    @State private var position: MapCameraPosition = .automatic

    private var visibleEpisodes: [TimelineEpisode] {
        let suppressed = TimelineVisibility.suppressedEpisodeIDs(from: assertions)
        return episodes.filter { !suppressed.contains($0.id) }
    }

    private var summaries: [HistoryPlaceSummary] {
        var staysByPlaceID: [UUID: [TimelineEpisode]] = [:]
        for episode in visibleEpisodes where episode.kind == .stay {
            guard let placeID = episode.placeID else { continue }
            staysByPlaceID[placeID, default: []].append(episode)
        }

        return places.compactMap { place in
            guard let visits = staysByPlaceID[place.id], !visits.isEmpty else { return nil }

            let latest = visits.max { $0.startDate < $1.startDate }
            return HistoryPlaceSummary(
                id: place.id,
                displayName: place.isPrivate ? "非公開の場所" : place.name,
                latitude: place.latitude,
                longitude: place.longitude,
                visitCount: visits.count,
                latestVisitDate: latest?.startDate,
                latestDay: latest.map { TimelineDayProjection.day(for: $0) },
                isPrivate: place.isPrivate
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.latestVisitDate, rhs.latestVisitDate) {
            case let (left?, right?):
                if left != right { return left > right }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var selectedSummary: HistoryPlaceSummary? {
        guard let selectedPlaceID else { return nil }
        return summaries.first { $0.id == selectedPlaceID }
    }

    var body: some View {
        if summaries.isEmpty {
            ContentUnavailableView {
                Label("まだ覚えた場所がありません", systemImage: "mappin.and.ellipse")
            } description: {
                Text("滞在場所を確認して覚えさせると、ここに自分の場所の地図が育っていきます。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, DS.horizontalPadding)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sectionSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("覚えた場所")
                            .font(.title2.bold())
                        Spacer()
                        Text("\(summaries.count)か所")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Map(position: $position, interactionModes: [.pan, .zoom]) {
                        ForEach(summaries) { summary in
                            Annotation(
                                summary.displayName,
                                coordinate: summary.coordinate
                            ) {
                                Button {
                                    select(summary)
                                } label: {
                                    HistoryPlaceMarker(isSelected: selectedPlaceID == summary.id)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(summary.displayName)を選択")
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: DS.contentCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.contentCornerRadius, style: .continuous)
                            .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
                    }
                    .sensoryFeedback(.selection, trigger: selectedPlaceID)

                    if let selectedSummary {
                        SelectedHistoryPlaceCard(summary: selectedSummary)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("場所")
                            .font(.headline)
                            .padding(.bottom, 2)

                        ForEach(summaries) { summary in
                            Button {
                                select(summary)
                            } label: {
                                HistoryPlaceRow(
                                    summary: summary,
                                    isSelected: selectedPlaceID == summary.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    private func select(_ summary: HistoryPlaceSummary) {
        withAnimation(reduceMotion ? nil : .snappy) {
            selectedPlaceID = summary.id
            position = .region(MKCoordinateRegion(
                center: summary.coordinate,
                latitudinalMeters: 1_400,
                longitudinalMeters: 1_400
            ))
        }
    }
}

private struct HistoryPlaceSummary: Identifiable {
    let id: UUID
    let displayName: String
    let latitude: Double
    let longitude: Double
    let visitCount: Int
    let latestVisitDate: Date?
    let latestDay: CalendarDay?
    let isPrivate: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var visitSummary: String {
        let countText = "\(visitCount)回"
        guard let latestDay else { return countText }
        return "\(countText) · 最後 \(latestDay.month)月\(latestDay.day)日"
    }
}

private struct HistoryPlaceMarker: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: isSelected ? 36 : 30, height: isSelected ? 36 : 30)
                .shadow(radius: 3, y: 1)

            Circle()
                .fill(Color.accentColor)
                .frame(width: isSelected ? 19 : 15, height: isSelected ? 19 : 15)
        }
    }
}

private struct SelectedHistoryPlaceCard: View {
    let summary: HistoryPlaceSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.isPrivate ? "lock.fill" : "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.displayName)
                    .font(.headline)
                Text(summary.visitSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let latestDay = summary.latestDay {
                NavigationLink(value: latestDay) {
                    HStack(spacing: 4) {
                        Text("最後の記録")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("最後に訪れた日の記録を見る")
            }
        }
        .padding(14)
        .daytraceGlassSurface(cornerRadius: DS.contentCornerRadius, interactive: true)
    }
}

private struct HistoryPlaceRow: View {
    let summary: HistoryPlaceSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: summary.isPrivate ? "lock.circle" : "mappin.circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(summary.visitSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
