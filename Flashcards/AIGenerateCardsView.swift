//
//  AIGenerateCardsView.swift
//  Flashcards
//
//  Created by Jens Wolf on 25.05.26.
//

import SwiftData
import SwiftUI

struct AIGenerateCardsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [Deck]
    @ObservedObject var subscriptionManager: AISubscriptionManager
    @State private var topic = ""
    @State private var difficultyLevelIndex = 1
    @State private var deckName = "Mathe"
    @State private var cardCount = 12
    @State private var generatedCards: [AIGeneratedFlashcard] = []
    @State private var errorMessage: String?
    @State private var isGenerating = false

    private let service = AIFlashcardService()
    private let difficultyLevels = ["Einsteiger", "Grundlagen", "Fortgeschritten", "Studium", "Experte"]

    init(initialDeckName: String = "Mathe", subscriptionManager: AISubscriptionManager) {
        self.subscriptionManager = subscriptionManager
        _deckName = State(initialValue: initialDeckName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thema") {
                    TextField("z. B. Brüche, Simple Past, Photosynthese", text: $topic)
                    Stepper(value: $difficultyLevelIndex, in: 0...4) {
                        Text(LocalizedStringKey(difficultyLevel))
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $cardCount, in: 5...20) {
                        Text(localizedCardCount(cardCount))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Stapel") {
                    LabeledContent("Zielstapel", value: deckName)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if !generatedCards.isEmpty {
                    Section("Vorschau") {
                        ForEach($generatedCards) { $card in
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Frage", text: $card.question, axis: .vertical)
                                    .font(.headline)
                                    .onChange(of: card.question) { _, value in
                                        card.question = FlashcardTextLimits.limited(value, to: FlashcardTextLimits.question)
                                    }

                                TextField("Antwort", text: $card.answer, axis: .vertical)
                                    .onChange(of: card.answer) { _, value in
                                        card.answer = FlashcardTextLimits.limited(value, to: FlashcardTextLimits.answer)
                                    }

                                Button(role: .destructive) {
                                    generatedCards.removeAll { $0.id == card.id }
                                } label: {
                                    Label("Karte entfernen", systemImage: "trash")
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("KI-Karten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if generatedCards.isEmpty {
                        Button {
                            Task {
                                await generateCards()
                            }
                        } label: {
                            if isGenerating {
                                ProgressView()
                            } else {
                                Label("Erstellen", systemImage: "sparkles")
                            }
                        }
                        .disabled(isGenerating || trimmedTopic.isEmpty || trimmedDeckName.isEmpty)
                    } else {
                        Button("Speichern") {
                            saveGeneratedCards()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var trimmedTopic: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDeckName: String {
        deckName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var difficultyLevel: String {
        difficultyLevels[difficultyLevelIndex]
    }

    private var answerLanguageCode: String {
        decks.first { $0.name == trimmedDeckName }?.languageCode ?? DeckLanguage.defaultCode
    }

    private func generateCards() async {
        isGenerating = true
        errorMessage = nil

        do {
            generatedCards = try await service.generateCards(
                topic: trimmedTopic,
                difficultyLevel: difficultyLevel,
                count: cardCount,
                deckName: trimmedDeckName,
                answerLanguageCode: answerLanguageCode,
                appStoreTransactionJWS: subscriptionManager.currentEntitlementJWS
            )
            generatedCards = generatedCards.map { card in
                AIGeneratedFlashcard(
                    question: FlashcardTextLimits.limited(card.question, to: FlashcardTextLimits.question),
                    answer: FlashcardTextLimits.limited(card.answer, to: FlashcardTextLimits.answer),
                    questionSpeechSegments: card.questionSpeechSegments,
                    answerSpeechSegments: card.answerSpeechSegments,
                    deckName: card.deckName
                )
            }

            if generatedCards.isEmpty {
                errorMessage = String(localized: "Die KI hat keine Karten erzeugt.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private func saveGeneratedCards() {
        let fallbackDeckName = trimmedDeckName.isEmpty ? "KI" : trimmedDeckName

        withAnimation {
            ensureDeckExists(named: fallbackDeckName, languageCode: answerLanguageCode)

            for card in generatedCards {
                let question = FlashcardTextLimits.limited(card.question.trimmingCharacters(in: .whitespacesAndNewlines), to: FlashcardTextLimits.question)
                let answer = FlashcardTextLimits.limited(card.answer.trimmingCharacters(in: .whitespacesAndNewlines), to: FlashcardTextLimits.answer)

                guard !question.isEmpty, !answer.isEmpty else { continue }

                modelContext.insert(Flashcard(question: question, answer: answer, deckName: fallbackDeckName, questionSpeechSegments: card.questionSpeechSegments, answerSpeechSegments: card.answerSpeechSegments))
            }
        }
    }

    private func ensureDeckExists(named deckName: String, languageCode: String = DeckLanguage.defaultCode) {
        let trimmedDeckName = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDeckName.isEmpty else { return }
        guard !decks.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedDeckName) == .orderedSame }) else { return }

        modelContext.insert(Deck(name: trimmedDeckName, languageCode: languageCode))
    }

    private func localizedCardCount(_ count: Int) -> String {
        String(format: String(localized: "%lld Karten"), Int64(count))
    }
}
