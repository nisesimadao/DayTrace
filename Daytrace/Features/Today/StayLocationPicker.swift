import MapKit
import SwiftUI

struct StayLocationPicker: View {
    @Binding var latitude: Double
    @Binding var longitude: Double

    let originalLatitude: Double
    let originalLongitude: Double

    @State private var position: MapCameraPosition
    @State private var feedbackTrigger = 0

    init(
        latitude: Binding<Double>,
        longitude: Binding<Double>,
        originalLatitude: Double,
        originalLongitude: Double
    ) {
        _latitude = latitude
        _longitude = longitude
        self.originalLatitude = originalLatitude
        self.originalLongitude = originalLongitude

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude.wrappedValue, longitude: longitude.wrappedValue),
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("地図を動かして、ピンを正しい場所に合わせます")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Map(position: $position, interactionModes: [.pan, .zoom])
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { context in
                    latitude = context.camera.centerCoordinate.latitude
                    longitude = context.camera.centerCoordinate.longitude
                    feedbackTrigger += 1
                }
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .offset(y: -18)
                        .accessibilityHidden(true)
                }
                .frame(height: 250)
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
                }
                .accessibilityLabel("滞在場所を修正する地図")
                .accessibilityHint("地図をパンまたは拡大縮小して、中央のピンを正しい場所に合わせます")

            HStack {
                Label("ピンの位置を保存します", systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("元の位置", systemImage: "arrow.uturn.backward") {
                    restoreOriginalLocation()
                }
                .font(.caption.weight(.semibold))
                .frame(minHeight: 44)
                .disabled(isAtOriginalLocation)
            }
        }
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
    }

    private var isAtOriginalLocation: Bool {
        abs(latitude - originalLatitude) < 0.000_001
            && abs(longitude - originalLongitude) < 0.000_001
    }

    private func restoreOriginalLocation() {
        latitude = originalLatitude
        longitude = originalLongitude
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: originalLatitude,
                longitude: originalLongitude
            ),
            latitudinalMeters: 500,
            longitudinalMeters: 500
        ))
        feedbackTrigger += 1
    }
}
