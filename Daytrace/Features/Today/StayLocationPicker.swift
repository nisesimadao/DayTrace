import MapKit
import SwiftUI

struct StayLocationPicker: View {
    let latitude: Double
    let longitude: Double
    let originalLatitude: Double
    let originalLongitude: Double
    let onEdit: () -> Void

    @State private var position: MapCameraPosition

    init(
        latitude: Double,
        longitude: Double,
        originalLatitude: Double,
        originalLongitude: Double,
        onEdit: @escaping () -> Void
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.originalLatitude = originalLatitude
        self.originalLongitude = originalLongitude
        self.onEdit = onEdit

        _position = State(initialValue: .region(Self.region(
            latitude: latitude,
            longitude: longitude
        )))
    }

    private var hasMovedFromOriginal: Bool {
        abs(latitude - originalLatitude) >= 0.000_001
            || abs(longitude - originalLongitude) >= 0.000_001
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.compactSpacing) {
            Button(action: onEdit) {
                ZStack(alignment: .bottomTrailing) {
                    Map(position: $position, interactionModes: []) {
                        Marker(
                            "選択中の場所",
                            coordinate: CLLocationCoordinate2D(
                                latitude: latitude,
                                longitude: longitude
                            )
                        )
                        .tint(Color.daytraceInk)
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .allowsHitTesting(false)

                    Label("場所を変更", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: .capsule)
                        .padding(10)
                }
                .frame(height: 164)
                .clipShape(.rect(cornerRadius: DS.controlCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.controlCornerRadius)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("場所を変更")
            .accessibilityHint("検索と大きな地図で滞在場所を選び直します")

            Label(
                hasMovedFromOriginal ? "修正した位置を選択中" : "記録された位置を選択中",
                systemImage: hasMovedFromOriginal ? "checkmark.circle.fill" : "location"
            )
            .font(.caption)
            .foregroundStyle(hasMovedFromOriginal ? Color.daytraceInk : Color.secondary)
        }
        .onChange(of: latitude) { _, _ in focusSelectedLocation() }
        .onChange(of: longitude) { _, _ in focusSelectedLocation() }
    }

    private func focusSelectedLocation() {
        position = .region(Self.region(latitude: latitude, longitude: longitude))
    }

    private static func region(latitude: Double, longitude: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 700,
            longitudinalMeters: 700
        )
    }
}
