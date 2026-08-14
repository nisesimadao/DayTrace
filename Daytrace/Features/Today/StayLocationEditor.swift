import MapKit
import SwiftUI

struct StayLocationEditor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let originalLatitude: Double
    let originalLongitude: Double
    let onConfirm: (Double, Double, String?) -> Void

    @State private var latitude: Double
    @State private var longitude: Double
    @State private var position: MapCameraPosition
    @State private var searchQuery = ""
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var selectedPlaceName: String?
    @State private var isSearchingPlaces = false
    @State private var searchErrorMessage: String?
    @State private var feedbackTrigger = 0

    init(
        latitude: Double,
        longitude: Double,
        originalLatitude: Double,
        originalLongitude: Double,
        onConfirm: @escaping (Double, Double, String?) -> Void
    ) {
        self.originalLatitude = originalLatitude
        self.originalLongitude = originalLongitude
        self.onConfirm = onConfirm
        _latitude = State(initialValue: latitude)
        _longitude = State(initialValue: longitude)
        _position = State(initialValue: .region(Self.region(
            latitude: latitude,
            longitude: longitude
        )))
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var isAtOriginalLocation: Bool {
        abs(latitude - originalLatitude) < 0.000_001
            && abs(longitude - originalLongitude) < 0.000_001
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, interactionModes: [.pan, .zoom])
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .all))
                .onMapCameraChange(frequency: .onEnd) { context in
                    updateDraftLocation(context.camera.centerCoordinate)
                }
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .offset(y: -20)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("滞在場所を選ぶ地図")
                .accessibilityHint("地図を動かし、中央のピンを正しい場所に合わせます")

            if !trimmedSearchQuery.isEmpty {
                PlaceSearchResultsPanel(
                    query: trimmedSearchQuery,
                    results: searchResults,
                    isLoading: isSearchingPlaces,
                    errorMessage: searchErrorMessage,
                    select: selectSearchResult
                )
                .padding(.horizontal, DS.horizontalPadding)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            StayLocationConfirmationBar(
                selectedPlaceName: selectedPlaceName,
                isAtOriginalLocation: isAtOriginalLocation,
                restoreOriginal: restoreOriginalLocation,
                confirm: confirmSelection
            )
            .padding(.horizontal, DS.horizontalPadding)
            .padding(.bottom, 8)
        }
        .navigationTitle("場所を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "施設名・住所を検索"
        )
        .task(id: trimmedSearchQuery) {
            await searchPlaces()
        }
        .animation(reduceMotion ? nil : .snappy, value: trimmedSearchQuery.isEmpty)
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
    }

    private func updateDraftLocation(_ newCoordinate: CLLocationCoordinate2D) {
        let movedFromSelectedPlace = abs(latitude - newCoordinate.latitude) >= 0.000_01
            || abs(longitude - newCoordinate.longitude) >= 0.000_01
        latitude = newCoordinate.latitude
        longitude = newCoordinate.longitude
        if movedFromSelectedPlace {
            selectedPlaceName = nil
        }
        feedbackTrigger += 1
    }

    private func searchPlaces() async {
        guard !trimmedSearchQuery.isEmpty else {
            searchResults = []
            searchErrorMessage = nil
            isSearchingPlaces = false
            return
        }

        isSearchingPlaces = true
        searchErrorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let results = try await PlaceSearchService.search(
                query: trimmedSearchQuery,
                near: coordinate
            )
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchErrorMessage = "場所を検索できませんでした。通信状態を確認してください。"
        }
        isSearchingPlaces = false
    }

    private func selectSearchResult(_ result: PlaceSearchResult) {
        latitude = result.latitude
        longitude = result.longitude
        selectedPlaceName = result.title
        searchQuery = ""
        searchResults = []
        searchErrorMessage = nil
        withAnimation(reduceMotion ? nil : .snappy) {
            position = .region(Self.region(
                latitude: result.latitude,
                longitude: result.longitude
            ))
        }
        feedbackTrigger += 1
    }

    private func restoreOriginalLocation() {
        latitude = originalLatitude
        longitude = originalLongitude
        selectedPlaceName = nil
        searchQuery = ""
        withAnimation(reduceMotion ? nil : .snappy) {
            position = .region(Self.region(
                latitude: originalLatitude,
                longitude: originalLongitude
            ))
        }
        feedbackTrigger += 1
    }

    private func confirmSelection() {
        onConfirm(latitude, longitude, selectedPlaceName)
        dismiss()
    }

    private static func region(latitude: Double, longitude: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 700,
            longitudinalMeters: 700
        )
    }
}
