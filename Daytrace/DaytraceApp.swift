import SwiftData
import SwiftUI

@main
struct DaytraceApp: App {
    private let container: ModelContainer = {
        let schema = Schema([
            LocationEvidence.self,
            VisitEvidence.self,
            PlaceRecord.self,
            TimelineEpisode.self,
            UserAssertion.self,
            JournalEntry.self,
            MomentNote.self,
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Daytrace store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(container)
    }
}
