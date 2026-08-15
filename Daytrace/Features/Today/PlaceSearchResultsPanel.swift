import SwiftUI

struct PlaceSearchResultsPanel: View {
    let query: String
    let results: [PlaceSearchResult]
    let isLoading: Bool
    let errorMessage: String?
    let select: (PlaceSearchResult) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("“\(query)”を検索中")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                } else if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.horizontal, 14)
                } else if results.isEmpty {
                    ContentUnavailableView.search
                        .frame(minHeight: 140)
                } else {
                    ForEach(results) { result in
                        Button {
                            select(result)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(Color.daytraceInk)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    if let subtitle = result.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 52)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if result.id != results.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 330)
        .background(.regularMaterial, in: .rect(cornerRadius: DS.contentCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DS.contentCornerRadius)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        }
    }
}
