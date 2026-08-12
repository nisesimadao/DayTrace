import CoreLocation
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LocationRecorder: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationRecorder()

    enum Health: Equatable {
        case notConfigured
        case needsPermission
        case limitedAccuracy
        case healthy
        case stale
        case unavailable(String)
    }

    private static let alwaysAuthorizationRequestedKey = "hasRequestedAlwaysAuthorization"

    private let manager = CLLocationManager()
    private var modelContext: ModelContext?
    private var configured = false
    private var standardUpdatesActive = false
    private var nextLocationSource: EvidenceSource?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy
    private(set) var lastEvidenceAt: Date?
    private(set) var isRecording = false
    private(set) var health: Health = .notConfigured
    private(set) var hasRequestedAlwaysAuthorization = UserDefaults.standard.bool(
        forKey: LocationRecorder.alwaysAuthorizationRequestedKey
    )

    var canRequestAlwaysInApp: Bool {
        authorizationStatus == .authorizedWhenInUse && !hasRequestedAlwaysAuthorization
    }

    override private init() {
        super.init()
        manager.delegate = self
        manager.activityType = .other
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
    }

    func attach(context: ModelContext) {
        modelContext = context
        let retention = RawEvidenceRetentionService()
        try? retention.backfillLegacyVisits(in: context)
        try? retention.prune(
            in: context,
            retentionDays: retentionDaysFromDefaults
        )
        lastEvidenceAt = nil
        restoreLastEvidenceDateIfNeeded()
    }

    func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        synchronizeAlwaysRequestState()
        refreshHealth()

        if isAuthorized {
            startPassiveRecording()
        }
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        guard canRequestAlwaysInApp else { return }
        hasRequestedAlwaysAuthorization = true
        UserDefaults.standard.set(true, forKey: Self.alwaysAuthorizationRequestedKey)
        manager.requestAlwaysAuthorization()
    }

    func startPassiveRecording() {
        guard CLLocationManager.locationServicesEnabled() else {
            health = .unavailable("位置情報サービスがオフです")
            return
        }
        guard isAuthorized else {
            refreshHealth()
            return
        }

        manager.startMonitoringVisits()
        manager.startMonitoringSignificantLocationChanges()
        isRecording = true

        if UserDefaults.standard.bool(forKey: "detailedRoutesEnabled") {
            startDetailedUpdates()
        } else {
            stopDetailedUpdates()
            requestForegroundSnapshot()
        }

        refreshHealth()
    }

    func setDetailedRoutesEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "detailedRoutesEnabled")
        guard isRecording else { return }
        enabled ? startDetailedUpdates() : stopDetailedUpdates()
    }

    func applyRetentionPolicy(days: Int) {
        UserDefaults.standard.set(days, forKey: "rawEvidenceRetentionDays")
        guard let context = modelContext else { return }

        let retention = RawEvidenceRetentionService()
        try? retention.backfillLegacyVisits(in: context)
        try? retention.prune(
            in: context,
            retentionDays: days
        )
        lastEvidenceAt = nil
        restoreLastEvidenceDateIfNeeded()
        refreshHealth()
    }

    func deleteRawLocationEvidence() throws {
        guard let context = modelContext else { return }
        try context.delete(model: LocationEvidence.self)
        try context.delete(model: VisitEvidence.self)
        try context.save()
        lastEvidenceAt = nil
        refreshHealth()
    }

    func deleteLocationHistoryKeepingJournal() throws {
        guard let context = modelContext else { return }
        try context.delete(model: LocationEvidence.self)
        try context.delete(model: VisitEvidence.self)
        try context.delete(model: TimelineEpisode.self)
        try context.delete(model: UserAssertion.self)
        try context.delete(model: PlaceRecord.self)
        try context.save()
        lastEvidenceAt = nil
        refreshHealth()
    }

    func requestForegroundSnapshot() {
        guard isAuthorized, CLLocationManager.locationServicesEnabled() else { return }
        guard !standardUpdatesActive else { return }
        nextLocationSource = .standardLocation
        manager.requestLocation()
    }

    func stopRecording() {
        stopDetailedUpdates()
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        isRecording = false
        refreshHealth()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        synchronizeAlwaysRequestState()
        refreshHealth()

        if isAuthorized {
            startPassiveRecording()
        } else {
            stopRecording()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let context = modelContext else { return }
        let zone = TimeZone.current.identifier
        let source = standardUpdatesActive ? EvidenceSource.standardLocation : (nextLocationSource ?? .significantChange)
        nextLocationSource = nil

        for location in locations where location.horizontalAccuracy >= 0 {
            guard location.timestamp.timeIntervalSinceNow > -5 * 60 else { continue }

            context.insert(LocationEvidence(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed,
                course: location.course,
                source: source,
                timeZoneIdentifier: zone
            ))
            lastEvidenceAt = max(lastEvidenceAt ?? .distantPast, location.timestamp)
        }

        try? context.save()
        try? TimelineEngine().rebuildRecentTimeline(in: context)
        refreshHealth()
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard let context = modelContext else { return }

        let arrival: Date? = visit.arrivalDate == .distantPast ? nil : visit.arrivalDate
        let departure: Date? = visit.departureDate == .distantFuture ? nil : visit.departureDate
        let observedAt = Date.now

        upsertVisit(
            arrival: arrival,
            departure: departure,
            observedAt: observedAt,
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            horizontalAccuracy: visit.horizontalAccuracy,
            in: context
        )

        let freshestDate = departure ?? arrival ?? observedAt
        lastEvidenceAt = max(lastEvidenceAt ?? .distantPast, freshestDate)
        try? context.save()
        try? TimelineEngine().rebuildRecentTimeline(in: context)
        refreshHealth()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        health = .unavailable(error.localizedDescription)
    }

    private var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    private var retentionDaysFromDefaults: Int {
        let defaults = UserDefaults.standard
        let key = "rawEvidenceRetentionDays"
        guard defaults.object(forKey: key) != nil else {
            defaults.set(90, forKey: key)
            return 90
        }
        return defaults.integer(forKey: key)
    }

    private func synchronizeAlwaysRequestState() {
        guard authorizationStatus == .authorizedAlways, !hasRequestedAlwaysAuthorization else { return }
        hasRequestedAlwaysAuthorization = true
        UserDefaults.standard.set(true, forKey: Self.alwaysAuthorizationRequestedKey)
    }

    private func startDetailedUpdates() {
        guard !standardUpdatesActive else { return }
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        if authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
        }
        manager.startUpdatingLocation()
        standardUpdatesActive = true
    }

    private func stopDetailedUpdates() {
        guard standardUpdatesActive else {
            manager.allowsBackgroundLocationUpdates = false
            return
        }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        standardUpdatesActive = false
    }

    private func restoreLastEvidenceDateIfNeeded() {
        guard lastEvidenceAt == nil, let context = modelContext else { return }

        var locationDescriptor = FetchDescriptor<LocationEvidence>(
            sortBy: [SortDescriptor(\LocationEvidence.timestamp, order: .reverse)]
        )
        locationDescriptor.fetchLimit = 1
        let latestLocation = try? context.fetch(locationDescriptor).first?.timestamp

        var visitDescriptor = FetchDescriptor<VisitEvidence>(
            sortBy: [SortDescriptor(\VisitEvidence.observedAt, order: .reverse)]
        )
        visitDescriptor.fetchLimit = 1
        let latestVisit = try? context.fetch(visitDescriptor).first
        let latestVisitDate = latestVisit.flatMap { $0.departureDate ?? $0.arrivalDate ?? $0.observedAt }

        lastEvidenceAt = [latestLocation, latestVisitDate]
            .compactMap { $0 }
            .max()
    }

    private func upsertVisit(
        arrival: Date?,
        departure: Date?,
        observedAt: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        in context: ModelContext
    ) {
        var descriptor = FetchDescriptor<VisitEvidence>(
            sortBy: [SortDescriptor(\VisitEvidence.observedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 32
        let recentVisits = (try? context.fetch(descriptor)) ?? []
        let coordinate = CLLocation(latitude: latitude, longitude: longitude)

        let matchingVisit: VisitEvidence? = recentVisits
            .compactMap { existing -> (VisitEvidence, Double)? in
                let existingLocation = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                let distance = coordinate.distance(from: existingLocation)

                if let arrival, let existingArrival = existing.arrivalDate {
                    let arrivalDelta = abs(existingArrival.timeIntervalSince(arrival))
                    let accuracyAllowance = min(
                        max(250, max(existing.horizontalAccuracy, horizontalAccuracy)),
                        1_000
                    )
                    guard arrivalDelta <= 120, distance <= accuracyAllowance else { return nil }
                    return (existing, arrivalDelta + distance / 100)
                }

                if arrival == nil, departure != nil, existing.departureDate == nil {
                    let observationAge = observedAt.timeIntervalSince(existing.observedAt)
                    guard observationAge >= 0, observationAge <= 12 * 60 * 60, distance <= 250 else {
                        return nil
                    }
                    return (existing, observationAge / 60 + distance / 100)
                }

                return nil
            }
            .min { $0.1 < $1.1 }?
            .0

        if let matchingVisit {
            if matchingVisit.arrivalDate == nil, let arrival {
                matchingVisit.arrivalDate = arrival
            }
            if let departure {
                matchingVisit.departureDate = departure
            }
            matchingVisit.observedAt = observedAt

            let existingAccuracy = matchingVisit.horizontalAccuracy
            if horizontalAccuracy >= 0 && (existingAccuracy < 0 || horizontalAccuracy < existingAccuracy) {
                matchingVisit.latitude = latitude
                matchingVisit.longitude = longitude
                matchingVisit.horizontalAccuracy = horizontalAccuracy
            }
            return
        }

        context.insert(VisitEvidence(
            arrivalDate: arrival,
            departureDate: departure,
            observedAt: observedAt,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            timeZoneIdentifier: TimeZone.current.identifier
        ))
    }

    private func refreshHealth(now: Date = .now) {
        switch authorizationStatus {
        case .notDetermined, .denied, .restricted:
            health = .needsPermission
        case .authorizedAlways, .authorizedWhenInUse:
            if accuracyAuthorization == .reducedAccuracy {
                health = .limitedAccuracy
            } else if let lastEvidenceAt, now.timeIntervalSince(lastEvidenceAt) > 6 * 60 * 60 {
                health = .stale
            } else {
                health = .healthy
            }
        @unknown default:
            health = .notConfigured
        }
    }
}

@MainActor
struct RawEvidenceRetentionService {
    func backfillLegacyVisits(in context: ModelContext) throws {
        let visits = try context.fetch(FetchDescriptor<VisitEvidence>())
        var changed = false

        for visit in visits where visit.observedAt == .distantPast {
            guard let bestKnownDate = visit.departureDate ?? visit.arrivalDate else { continue }
            visit.observedAt = bestKnownDate
            changed = true
        }

        if changed {
            try context.save()
        }
    }

    func prune(
        in context: ModelContext,
        retentionDays: Int,
        now: Date = .now
    ) throws {
        guard retentionDays > 0 else { return }

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: now
        ) ?? now.addingTimeInterval(-Double(retentionDays) * 86_400)

        try context.delete(
            model: LocationEvidence.self,
            where: #Predicate { $0.timestamp < cutoff }
        )

        let visits = try context.fetch(FetchDescriptor<VisitEvidence>())
        for visit in visits {
            let evidenceDate = visit.departureDate ?? visit.arrivalDate ?? visit.observedAt
            if evidenceDate < cutoff {
                context.delete(visit)
            }
        }

        try context.save()
    }
}
