//
//  FlashcardsTests.swift
//  FlashcardsTests
//
//  Created by Jens Wolf on 25.05.26.
//

import Testing
import Foundation
@testable import Flashcards

struct FlashcardsTests {

    @Test func flashcardTextLimitsTrimToMaximumLengths() {
        let longQuestion = String(repeating: "Q", count: FlashcardTextLimits.question + 25)
        let longAnswer = String(repeating: "A", count: FlashcardTextLimits.answer + 25)

        #expect(FlashcardTextLimits.limited(longQuestion, to: FlashcardTextLimits.question).count == FlashcardTextLimits.question)
        #expect(FlashcardTextLimits.limited(longAnswer, to: FlashcardTextLimits.answer).count == FlashcardTextLimits.answer)
    }

    @Test func flashcardInitialStateIsReadyForReview() {
        let beforeCreation = Date()
        let card = Flashcard(question: "Was ist 2 + 2?", answer: "4", deckName: "Mathe")
        let afterCreation = Date()

        #expect(card.question == "Was ist 2 + 2?")
        #expect(card.answer == "4")
        #expect(card.deckName == "Mathe")
        #expect(card.timesReviewed == 0)
        #expect(card.timesKnown == 0)
        #expect(card.timesUnsure == 0)
        #expect(card.timesAgain == 0)
        #expect(card.nextReviewDate >= beforeCreation)
        #expect(card.nextReviewDate <= afterCreation)
    }

    @Test func flashcardSpeechSegmentsRoundTripAndRecoverFromInvalidJSON() {
        let card = Flashcard(
            question: "What does casa mean?",
            answer: "Casa means Haus.",
            questionSpeechSegments: [
                FlashcardSpeechSegment(text: "What does casa mean?", languageCode: "de-DE")
            ],
            answerSpeechSegments: [
                FlashcardSpeechSegment(text: "Casa", languageCode: "es-ES"),
                FlashcardSpeechSegment(text: "means Haus.", languageCode: "de-DE")
            ]
        )

        #expect(card.questionSpeechSegments == [FlashcardSpeechSegment(text: "What does casa mean?", languageCode: "de-DE")])
        #expect(card.answerSpeechSegments == [
            FlashcardSpeechSegment(text: "Casa", languageCode: "es-ES"),
            FlashcardSpeechSegment(text: "means Haus.", languageCode: "de-DE")
        ])

        card.answerSpeechSegmentsJSON = "{bad json"
        #expect(card.answerSpeechSegments.isEmpty)
    }

    @Test func deckLanguageCatalogKeepsDefaultAndUniqueCodes() {
        let codes = DeckLanguage.all.map(\.code)

        #expect(DeckLanguage.defaultCode == "de-DE")
        #expect(codes.contains("de-DE"))
        #expect(codes.contains("en-US"))
        #expect(codes.contains("es-ES"))
        #expect(Set(codes).count == codes.count)
    }

    @Test func deckDefaultLanguageIsGerman() {
        let deck = Deck(name: "Musik")

        #expect(deck.name == "Musik")
        #expect(deck.languageCode == DeckLanguage.defaultCode)
    }

    @Test func answerTransformOptionsStayStableForBackendContract() {
        #expect(AnswerTransformOption.allCases.map(\.rawValue) == [
            "simplify",
            "example",
            "mnemonic",
            "mini_quiz",
            "child_friendly",
            "exam_answer"
        ])
    }

    @Test func aiRequestsRequireSubscriptionBeforeNetworkCall() async {
        do {
            _ = try await AIFlashcardService().generateCards(
                endpoint: "https://example.invalid/functions/v1/flashcards-ai",
                topic: "Brüche",
                difficultyLevel: "Einsteiger",
                count: 5,
                deckName: "Mathe",
                appStoreTransactionJWS: nil
            )
            Issue.record("AI card generation should require an active subscription before sending a network request.")
        } catch AIFlashcardError.subscriptionRequired {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func aiAnswerTransformsRequireSubscriptionBeforeNetworkCall() async {
        do {
            _ = try await AIFlashcardService().transformAnswer(
                endpoint: "https://example.invalid/functions/v1/flashcards-ai",
                question: "Was ist Photosynthese?",
                answer: "Pflanzen wandeln Licht in Energie um.",
                option: .simplify,
                appStoreTransactionJWS: ""
            )
            Issue.record("AI answer transforms should require an active subscription before sending a network request.")
        } catch AIFlashcardError.subscriptionRequired {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func cloudConfigurationUsesSharedSupabaseEndpoint() {
        let endpoint = CloudConfiguration.supabaseAIEndpoint

        #expect(endpoint == "https://skdwvepjmmotncasvbgy.supabase.co/functions/v1/flashcards-ai")
        #expect(URL(string: endpoint)?.scheme == "https")
    }

    @Test func aiSubscriptionProductIDMatchesStoreKitConfiguration() throws {
        let storeKitConfigurationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Flashcards")
            .appending(path: "Flashcards.storekit")

        let data = try Data(contentsOf: storeKitConfigurationURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let groups = json?["subscriptionGroups"] as? [[String: Any]]
        let productIDs = groups?
            .flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
            .compactMap { $0["productID"] as? String } ?? []

        #expect(productIDs.contains(AISubscriptionManager.monthlyProductID))
    }

    @Test func appStoreSubscriptionMetadataIsCompleteEnoughForLocalTesting() throws {
        let storeKitConfigurationURL = projectFile(named: "Flashcards.storekit")
        let data = try Data(contentsOf: storeKitConfigurationURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let groups = json?["subscriptionGroups"] as? [[String: Any]] ?? []
        let aiSubscription = groups
            .flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
            .first { $0["productID"] as? String == AISubscriptionManager.monthlyProductID }

        #expect(aiSubscription?["recurringSubscriptionPeriod"] as? String == "P1M")
        #expect(aiSubscription?["type"] as? String == "RecurringSubscription")
        #expect(aiSubscription?["displayPrice"] as? String == "2.99")

        let localizations = aiSubscription?["localizations"] as? [[String: Any]] ?? []
        let locales = Set(localizations.compactMap { $0["locale"] as? String })
        #expect(locales.contains("de_DE"))
        #expect(locales.contains("en_US"))
    }

    @Test func paywallDoesNotContainLegacyLoadingPriceButton() throws {
        let contentViewURL = projectFile(named: "ContentView.swift")
        let source = try String(contentsOf: contentViewURL, encoding: .utf8)

        #expect(!source.contains("Für \\(subscriptionManager.monthlyPriceText) pro Monat aktivieren"))
        #expect(source.contains("ProductView(id: AISubscriptionManager.monthlyProductID"))
    }

    @Test func releaseBuildDoesNotExposeDangerousDemoDeleteButton() throws {
        let contentViewURL = projectFile(named: "ContentView.swift")
        let source = try String(contentsOf: contentViewURL, encoding: .utf8)

        #expect(!source.contains("Alle Karten löschen"))
    }

    private func projectFile(named fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Flashcards")
            .appending(path: fileName)
    }
}
