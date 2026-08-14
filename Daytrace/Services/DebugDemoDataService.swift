#if DEBUG
import Foundation
import SwiftData

@MainActor
struct DebugDemoDataService {
    private enum ID {
        static let places = [
            UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "D0000000-0000-4000-8000-000000000002")!,
            UUID(uuidString: "D0000000-0000-4000-8000-000000000003")!
        ]
        static let episodes = (1...8).map {
            UUID(uuidString: String(format: "D1000000-0000-4000-8000-%012d", $0))!
        }
        static let journals = (1...5).map {
            UUID(uuidString: String(format: "D2000000-0000-4000-8000-%012d", $0))!
        }
        static let notes = (1...3).map {
            UUID(uuidString: String(format: "D3000000-0000-4000-8000-%012d", $0))!
        }
    }

    func isInstalled(in context: ModelContext) throws -> Bool {
        let demoIDs = Set(ID.journals)
        return try context.fetch(FetchDescriptor<JournalEntry>()).contains { demoIDs.contains($0.id) }
    }

    func install(in context: ModelContext, now: Date = .now) throws {
        guard try !isInstalled(in: context) else { return }
        try remove(in: context)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let zone = TimeZone.current.identifier

        let places = [
            PlaceRecord(id: ID.places[0], name: "朝の喫茶店", latitude: 35.6816, longitude: 139.7655, source: .userConfirmed),
            PlaceRecord(id: ID.places[1], name: "川沿いの公園", latitude: 35.6764, longitude: 139.7520, source: .userConfirmed),
            PlaceRecord(id: ID.places[2], name: "小さな本屋", latitude: 35.6896, longitude: 139.7006, source: .userConfirmed)
        ]
        places.forEach { context.insert($0) }

        let stays: [(day: Int, hour: Int, duration: Int, title: String, place: Int)] = [
            (0, 8, 70, "朝の喫茶店", 0),
            (0, 18, 55, "川沿いの公園", 1),
            (1, 12, 45, "小さな本屋", 2),
            (2, 9, 90, "朝の喫茶店", 0),
            (2, 16, 80, "川沿いの公園", 1),
            (4, 11, 50, "小さな本屋", 2),
            (6, 8, 60, "朝の喫茶店", 0),
            (6, 15, 75, "川沿いの公園", 1)
        ]

        for (index, stay) in stays.enumerated() {
            let start = date(dayOffset: -stay.day, hour: stay.hour, from: today, calendar: calendar)
            let place = places[stay.place]
            context.insert(TimelineEpisode(
                id: ID.episodes[index],
                kind: .stay,
                startDate: start,
                endDate: start.addingTimeInterval(TimeInterval(stay.duration * 60)),
                title: stay.title,
                subtitle: "デモの滞在",
                latitude: place.latitude,
                longitude: place.longitude,
                confidence: .high,
                placeID: place.id,
                sourceVersion: 99,
                timeZoneIdentifier: zone
            ))
        }

        let journalBodies = [
            "朝は窓際でコーヒー。夕方の風が気持ちよくて、少し遠回りして帰った。",
            "偶然入った本屋で、ずっと探していた本を見つけた。",
            "予定を詰めすぎず、川沿いでぼんやりできた日。",
            "雨の音を聞きながら家でゆっくりした。",
            "久しぶりの人に会えて、帰り道まで嬉しかった。"
        ]
        let journalDays = [0, 1, 2, 4, 6]
        for index in journalBodies.indices {
            let anchor = date(dayOffset: -journalDays[index], hour: 0, from: today, calendar: calendar)
            context.insert(JournalEntry(
                id: ID.journals[index],
                dayAnchor: anchor,
                body: journalBodies[index],
                createdAt: anchor.addingTimeInterval(20 * 60 * 60),
                updatedAt: anchor.addingTimeInterval(21 * 60 * 60),
                timeZoneIdentifier: zone
            ))
        }

        let notes: [(day: Int, hour: Int, body: String)] = [
            (0, 14, "帰りに牛乳を買う"),
            (1, 16, "本の表紙がきれいだった"),
            (4, 10, "雨の匂い")
        ]
        for (index, note) in notes.enumerated() {
            context.insert(MomentNote(
                id: ID.notes[index],
                timestamp: date(dayOffset: -note.day, hour: note.hour, from: today, calendar: calendar),
                body: note.body,
                timeZoneIdentifier: zone
            ))
        }

        try context.save()
    }

    func remove(in context: ModelContext) throws {
        let placeIDs = Set(ID.places)
        let episodeIDs = Set(ID.episodes)
        let journalIDs = Set(ID.journals)
        let noteIDs = Set(ID.notes)

        try context.fetch(FetchDescriptor<PlaceRecord>())
            .filter { placeIDs.contains($0.id) }
            .forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<TimelineEpisode>())
            .filter { episodeIDs.contains($0.id) }
            .forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<JournalEntry>())
            .filter { journalIDs.contains($0.id) }
            .forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<MomentNote>())
            .filter { noteIDs.contains($0.id) }
            .forEach { context.delete($0) }

        try context.save()
    }

    private func date(dayOffset: Int, hour: Int, from today: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
    }
}
#endif
