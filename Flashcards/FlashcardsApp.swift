//
//  FlashcardsApp.swift
//  Flashcards
//
//  Created by Jens Wolf on 25.05.26.
//

import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Flashcard.self,
            Deck.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(CloudConfiguration.iCloudContainerIdentifier)
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
