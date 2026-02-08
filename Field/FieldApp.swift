import SwiftUI
import SwiftData

@main
struct FieldApp: App {
    // Database Setup
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Session.self, // Ensure "Session.swift" exists and is correct
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            // CRITICAL CHANGE: We are loading HomeView instead of ContentView
            HomeView()
        }
        .modelContainer(sharedModelContainer)
    }
}
