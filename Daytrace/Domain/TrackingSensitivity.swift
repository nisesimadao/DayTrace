import CoreLocation
import Foundation

enum TrackingSensitivity: String, CaseIterable, Identifiable, Sendable {
    case lowPower
    case balanced
    case highPrecision

    static let storageKey = "trackingSensitivity"
    private static let legacyDetailedRoutesKey = "detailedRoutesEnabled"

    var id: String { rawValue }

    static var current: TrackingSensitivity {
        let defaults = UserDefaults.standard
        if let rawValue = defaults.string(forKey: storageKey),
           let sensitivity = TrackingSensitivity(rawValue: rawValue) {
            return sensitivity
        }

        if defaults.bool(forKey: legacyDetailedRoutesKey) {
            return .highPrecision
        }
        return .lowPower
    }

    static func persist(_ sensitivity: TrackingSensitivity) {
        let defaults = UserDefaults.standard
        defaults.set(sensitivity.rawValue, forKey: storageKey)
        defaults.set(sensitivity.usesContinuousUpdates, forKey: legacyDetailedRoutesKey)
    }

    var title: String {
        switch self {
        case .lowPower: "省電力"
        case .balanced: "標準"
        case .highPrecision: "高精度"
        }
    }

    var shortDescription: String {
        switch self {
        case .lowPower:
            "iOSの訪問検出を中心に、バッテリーを優先"
        case .balanced:
            "20分前後の停車も拾いやすくする"
        case .highPrecision:
            "10分前後の停車まで拾いやすくする"
        }
    }

    var batteryDescription: String {
        switch self {
        case .lowPower: "低"
        case .balanced: "中"
        case .highPrecision: "高"
        }
    }

    var usesContinuousUpdates: Bool {
        self != .lowPower
    }

    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .lowPower: kCLLocationAccuracyHundredMeters
        case .balanced: kCLLocationAccuracyHundredMeters
        case .highPrecision: kCLLocationAccuracyNearestTenMeters
        }
    }

    var distanceFilter: CLLocationDistance {
        switch self {
        case .lowPower: 100
        case .balanced: 75
        case .highPrecision: 25
        }
    }

    var inferredStopMinimumDuration: TimeInterval? {
        switch self {
        case .lowPower: nil
        case .balanced: 20 * 60
        case .highPrecision: 10 * 60
        }
    }

    var inferredStopRadius: CLLocationDistance {
        switch self {
        case .lowPower: 0
        case .balanced: 220
        case .highPrecision: 160
        }
    }

    var inferredStopMaximumAccuracy: CLLocationAccuracy {
        switch self {
        case .lowPower: 0
        case .balanced: 250
        case .highPrecision: 150
        }
    }

    var persistedRouteMinimumInterval: TimeInterval {
        switch self {
        case .lowPower: 0
        case .balanced: 30
        case .highPrecision: 20
        }
    }

    var persistedRouteMinimumDistance: CLLocationDistance {
        switch self {
        case .lowPower: 0
        case .balanced: 80
        case .highPrecision: 35
        }
    }

    var persistedStationarySampleInterval: TimeInterval {
        switch self {
        case .lowPower: 0
        case .balanced: 10 * 60
        case .highPrecision: 5 * 60
        }
    }
}
