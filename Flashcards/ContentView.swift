//
//  ContentView.swift
//  Flashcards
//
//  Created by Jens Wolf on 25.05.26.
//

import SwiftUI
import SwiftData
import CloudKit
import AVFoundation
import Combine
import StoreKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var flashcards: [Flashcard]
    @Query private var decks: [Deck]
    @StateObject private var subscriptionManager = AISubscriptionManager()
    @State private var showingAddCardSheet = false
    @State private var showingAddDeckSheet = false
    @State private var newQuestion = ""
    @State private var newAnswer = ""
    @State private var newDeckName = "Allgemein"
    @State private var newDeckOnlyName = ""
    @State private var newDeckLanguageCode = ""
    @State private var selectedDeckName = "Alle"
    @State private var aiDeckSelection: AIDeckSelection?
    @State private var deckPendingDeletion: String?
    @State private var deckBeingEdited: String?
    @State private var editedDeckName = ""
    @State private var editedDeckLanguageCode = ""
    @State private var navigationPath: [NavigationRoute] = []
    @State private var showingSettingsSheet = false
    @State private var showingAIPaywall = false
    @State private var showingSettingsAIPaywall = false
    @State private var demoCardsCreatedMessage: String?
    @AppStorage("knownReviewDays") private var knownReviewDays = 7
    @AppStorage("unsureReviewDays") private var unsureReviewDays = 1
    @AppStorage("againReviewDays") private var againReviewDays = 0
    @State private var showIntro = !ProcessInfo.processInfo.arguments.contains("UITEST_SKIP_INTRO")

    private var deckNames: [String] {
        let names = Set(flashcards.map { $0.deckName } + decks.map { $0.name })
        return names.sorted()
    }

    private func sortedFlashcards(in deckName: String) -> [Flashcard] {
        flashcards
            .filter { $0.deckName == deckName }
            .sorted {
                if $0.nextReviewDate == $1.nextReviewDate {
                    return $0.question < $1.question
                }
                return $0.nextReviewDate < $1.nextReviewDate
            }
    }

    private func languageCode(for deckName: String) -> String {
        decks.first { $0.name == deckName }?.languageCode ?? DeckLanguage.defaultCode
    }

    var body: some View {
        ZStack {
            mainContent
                .opacity(showIntro ? 0 : 1)

            if showIntro {
                IntroView {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        showIntro = false
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var mainContent: some View {
        NavigationStack(path: $navigationPath) {
            deckOverview
                .navigationTitle("Study Cards")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingSettingsSheet = true
                        } label: {
                            Label("Einstellungen", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("settingsButton")
                    }
                }
                .navigationDestination(for: NavigationRoute.self) { route in
                    switch route {
                    case .deckDetail(let deckName):
                        deckDetailView(deckName: deckName)
                    case .deckCards(let deckName):
                        deckCardsListView(deckName: deckName)
                    }
                }
        }
        .sheet(isPresented: $showingAddCardSheet) {
            NavigationStack {
                Form {
                    Section("Frage") {
                        TextField("z. B. Was ist die Hauptstadt von Frankreich?", text: $newQuestion, axis: .vertical)
                            .onChange(of: newQuestion) { _, value in
                                newQuestion = FlashcardTextLimits.limited(value, to: FlashcardTextLimits.question)
                            }
                            .accessibilityIdentifier("newCardQuestionField")
                    }

                    Section("Antwort") {
                        TextField("z. B. Paris", text: $newAnswer, axis: .vertical)
                            .onChange(of: newAnswer) { _, value in
                                newAnswer = FlashcardTextLimits.limited(value, to: FlashcardTextLimits.answer)
                            }
                            .accessibilityIdentifier("newCardAnswerField")
                    }

                    Section("Stapel") {
                        TextField("z. B. Englisch, Mathe, Bio", text: $newDeckName)
                            .accessibilityIdentifier("newCardDeckField")
                    }
                }
                .navigationTitle("Neue Karte")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            resetAddCardForm()
                            showingAddCardSheet = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            addItem()
                            showingAddCardSheet = false
                        }
                        .disabled(newQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddDeckSheet) {
            NavigationStack {
                Form {
                    Section("Stapel") {
                        TextField("z. B. Mathe, Englisch, Bio", text: $newDeckOnlyName)
                            .accessibilityIdentifier("newDeckNameField")

                        Picker("Sprache", selection: $newDeckLanguageCode) {
                            Text("Bitte auswählen").tag("")

                            ForEach(DeckLanguage.all) { language in
                                Text(LocalizedStringKey(language.name)).tag(language.code)
                            }
                        }
                        .accessibilityIdentifier("newDeckLanguagePicker")
                    }
                }
                .navigationTitle("Neuer Stapel")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            newDeckOnlyName = ""
                            newDeckLanguageCode = ""
                            showingAddDeckSheet = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            addDeck()
                            showingAddDeckSheet = false
                        }
                        .disabled(newDeckOnlyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newDeckLanguageCode.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: isEditDeckSheetPresented) {
            NavigationStack {
                Form {
                    Section("Stapel") {
                        TextField("Titel", text: $editedDeckName)
                            .accessibilityIdentifier("editDeckNameField")

                        Picker("Sprache", selection: $editedDeckLanguageCode) {
                            Text("Bitte auswählen").tag("")

                            ForEach(DeckLanguage.all) { language in
                                Text(LocalizedStringKey(language.name)).tag(language.code)
                            }
                        }
                        .accessibilityIdentifier("editDeckLanguagePicker")
                    }
                }
                .navigationTitle("Stapel bearbeiten")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            resetEditDeckForm()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            if let deckBeingEdited {
                                updateDeck(named: deckBeingEdited, newName: editedDeckName, languageCode: editedDeckLanguageCode)
                            }
                            resetEditDeckForm()
                        }
                        .disabled(editedDeckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedDeckLanguageCode.isEmpty)
                    }
                }
            }
        }
        .sheet(item: $aiDeckSelection) { selection in
            AIGenerateCardsView(initialDeckName: selection.deckName, subscriptionManager: subscriptionManager)
        }
        .sheet(isPresented: $showingAIPaywall) {
            AIPaywallView(subscriptionManager: subscriptionManager)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                Form {
                    Section("Account & Sync") {
                        CloudSyncStatusView()
                    }

                    AISubscriptionSettingsSection(subscriptionManager: subscriptionManager) {
                        showingSettingsAIPaywall = true
                    }

                    Section("Wiederholungsrate") {
                        Stepper(value: $knownReviewDays, in: 1...30) {
                            Text(localizedReviewIntervalLabel(titleKey: "Gewusst", days: knownReviewDays))
                        }
                        Stepper(value: $unsureReviewDays, in: 1...14) {
                            Text(localizedReviewIntervalLabel(titleKey: "Unsicher", days: unsureReviewDays))
                        }
                        Stepper(value: $againReviewDays, in: 0...7) {
                            Text(localizedReviewIntervalLabel(titleKey: "Nochmal", days: againReviewDays))
                        }
                    }

                    SpeechSettingsSection()

                    Section("Hinweis") {
                        Text("Diese Werte gelten für neue Bewertungen. Bereits bewertete Karten werden nicht rückwirkend geändert.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Demo") {
                        Button("Demo-Daten erstellen") {
                            createDemoCards()
                        }

                        if let demoCardsCreatedMessage {
                            Label(demoCardsCreatedMessage, systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .navigationTitle("Einstellungen")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") {
                            showingSettingsSheet = false
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettingsAIPaywall) {
                AIPaywallView(subscriptionManager: subscriptionManager)
            }
        }
        .alert("Stapel löschen?", isPresented: isDeleteDeckAlertPresented) {
            Button("Abbrechen", role: .cancel) {
                deckPendingDeletion = nil
            }

            Button("Löschen", role: .destructive) {
                if let deckPendingDeletion {
                    deleteDeck(named: deckPendingDeletion)
                }
                deckPendingDeletion = nil
            }
        } message: {
            Text("Der Stapel und alle enthaltenen Karten werden gelöscht.")
        }
    }

    private var deckOverview: some View {
        let dueCards = flashcards
            .filter { $0.nextReviewDate <= Date() }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }

        return ZStack {
            OverviewBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DeckOverviewHeroView(cardCount: flashcards.count, dueCards: dueCards.count) {
                        if let firstDueCard = dueCards.first {
                            NavigationLink {
                                StudyCardView(cards: flashcards, startCard: firstDueCard, speechLanguageCode: languageCode(for: firstDueCard.deckName), subscriptionManager: subscriptionManager)
                            } label: {
                                Label("Lernen", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.orange)
                        } else {
                            Label("Nichts fällig", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(.green)
                                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Deine Stapel")
                            .font(.title2.bold())

                        Spacer()

                        Text(localizedDeckCount(deckNames.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 16)], spacing: 16) {
                        ForEach(Array(deckNames.enumerated()), id: \.element) { index, deckName in
                            let cards = sortedFlashcards(in: deckName)

                            NavigationLink(value: NavigationRoute.deckDetail(deckName)) {
                                DeckTileView(deckName: deckName, cardCount: cards.count, dueCount: cards.filter { $0.nextReviewDate <= Date() }.count, accent: DeckTileStyle.accent(for: index))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("deckTile_\(deckName)")
                        }

                        Button {
                            newDeckOnlyName = ""
                            showingAddDeckSheet = true
                        } label: {
                            AddDeckTileView()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("addDeckButton")
                    }
                }
                .padding()
            }
        }
        .overlay {
            if deckNames.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.blue, .purple)

                    Text("Lerne mit Teresa")
                        .font(.title.bold())

                    Text("Erstelle deinen ersten Stapel und starte deine Lernrunde.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        newDeckOnlyName = ""
                        showingAddDeckSheet = true
                    } label: {
                        Label("Neuer Stapel", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("addDeckButton")
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding()
            }
        }
    }

    private func deckDetailView(deckName: String) -> some View {
        let cards = sortedFlashcards(in: deckName)
        let dueCards = cards.filter { $0.nextReviewDate <= Date() }
        let futureCardsCount = cards.filter { $0.nextReviewDate > Date() }.count
        let knownCardsCount = cards.filter { $0.timesKnown > 0 }.count

        return VStack(spacing: 0) {
            studyActionBar(cards: cards, dueCards: dueCards)

            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Statistik")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            statChip(title: "Gesamt", value: cards.count, systemImage: "square.stack.3d.up", tint: .blue)
                            statChip(title: "Heute", value: dueCards.count, systemImage: "flame.fill", tint: .orange)
                            statChip(title: "Später", value: futureCardsCount, systemImage: "calendar", tint: .purple)
                            statChip(title: "Gewusst", value: knownCardsCount, systemImage: "checkmark.circle.fill", tint: .green)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink(value: NavigationRoute.deckCards(deckName)) {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.square.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Fragen")
                                    .font(.headline)

                                Text(localizedCardsInDeckCount(cards.count))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(deckName)
        .toolbar {
            ToolbarItem {
                Button {
                    editedDeckName = deckName
                    editedDeckLanguageCode = languageCode(for: deckName)
                    deckBeingEdited = deckName
                } label: {
                    Label("Stapel bearbeiten", systemImage: "pencil")
                }
                .accessibilityIdentifier("editDeckButton")
            }

            ToolbarItem {
                Button(role: .destructive) {
                    deckPendingDeletion = deckName
                } label: {
                    Label("Stapel löschen", systemImage: "trash")
                }
                .accessibilityIdentifier("deleteDeckButton")
            }
        }
    }

    private func deckCardsListView(deckName: String) -> some View {
        let cards = sortedFlashcards(in: deckName)

        return List {
            Section {
                ForEach(cards) { card in
                    NavigationLink {
                        StudyCardView(cards: cards, startCard: card, speechLanguageCode: languageCode(for: deckName), subscriptionManager: subscriptionManager)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.question)
                                .font(.headline)

                            Text(card.reviewStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { offsets in
                    deleteCards(cards, offsets: offsets)
                }
            }
        }
        .navigationTitle("Fragen")
        .toolbar {
            ToolbarItem {
                Button {
                    if subscriptionManager.hasActiveSubscription {
                        aiDeckSelection = AIDeckSelection(deckName: deckName)
                    } else {
                        showingAIPaywall = true
                    }
                } label: {
                    Label("KI-Karten", systemImage: "sparkles")
                }
                .accessibilityIdentifier("questionsListAIButton")
            }

            ToolbarItem {
                Button {
                    selectedDeckName = deckName
                    newDeckName = deckName
                    showingAddCardSheet = true
                } label: {
                    Label("Neue Karte", systemImage: "plus")
                }
                .accessibilityIdentifier("questionsListAddCardButton")
            }
        }
    }

    private var isDeleteDeckAlertPresented: Binding<Bool> {
        Binding(
            get: { deckPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    deckPendingDeletion = nil
                }
            }
        )
    }

    private var isEditDeckSheetPresented: Binding<Bool> {
        Binding(
            get: { deckBeingEdited != nil },
            set: { isPresented in
                if !isPresented {
                    resetEditDeckForm()
                }
            }
        )
    }

    private func studyActionBar(cards: [Flashcard], dueCards: [Flashcard]) -> some View {
        HStack {
            if let firstDueCard = dueCards.first {
                NavigationLink {
                    StudyCardView(cards: cards, startCard: firstDueCard, speechLanguageCode: firstDueCard.deckName.isEmpty ? DeckLanguage.defaultCode : languageCode(for: firstDueCard.deckName), subscriptionManager: subscriptionManager)
                } label: {
                    Label("Lernen", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("Nichts fällig", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(.secondary)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.background)
    }

    private func statChip(title: String, value: Int, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)

                Text("\(value)")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
            }

            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        }
    }

    private func addItem() {
        let question = FlashcardTextLimits.limited(newQuestion.trimmingCharacters(in: .whitespacesAndNewlines), to: FlashcardTextLimits.question)
        let answer = FlashcardTextLimits.limited(newAnswer.trimmingCharacters(in: .whitespacesAndNewlines), to: FlashcardTextLimits.answer)
        let trimmedDeckName = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        let deckName = trimmedDeckName.isEmpty ? "Allgemein" : trimmedDeckName

        guard !question.isEmpty, !answer.isEmpty else { return }

        withAnimation {
            ensureDeckExists(named: deckName)
            let newCard = Flashcard(question: question, answer: answer, deckName: deckName)
            modelContext.insert(newCard)
            resetAddCardForm()
        }
    }

    private func addDeck() {
        let deckName = newDeckOnlyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deckName.isEmpty, !newDeckLanguageCode.isEmpty else { return }

        withAnimation {
            ensureDeckExists(named: deckName, languageCode: newDeckLanguageCode)
            selectedDeckName = deckName
            newDeckOnlyName = ""
            newDeckLanguageCode = ""
        }
    }

    private func ensureDeckExists(named deckName: String, languageCode: String = DeckLanguage.defaultCode) {
        let trimmedDeckName = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDeckName.isEmpty else { return }
        guard !decks.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedDeckName) == .orderedSame }) else { return }

        modelContext.insert(Deck(name: trimmedDeckName, languageCode: languageCode))
    }

    private func deleteCards(_ cards: [Flashcard], offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(cards[index])
            }
        }
    }

    private func deleteDeck(named deckName: String) {
        withAnimation {
            for card in flashcards where card.deckName == deckName {
                modelContext.delete(card)
            }

            for deck in decks where deck.name == deckName {
                modelContext.delete(deck)
            }

            if selectedDeckName == deckName {
                selectedDeckName = "Alle"
            }

            navigationPath = []
        }
    }

    private func updateDeck(named oldName: String, newName proposedName: String, languageCode: String) {
        let newName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, !languageCode.isEmpty else { return }

        withAnimation {
            for card in flashcards where card.deckName == oldName {
                card.deckName = newName
                card.updatedAt = Date()
            }

            let updatedDeck: Deck
            if let existingDeck = decks.first(where: { $0.name == oldName }) {
                existingDeck.name = newName
                existingDeck.languageCode = languageCode
                existingDeck.updatedAt = Date()
                updatedDeck = existingDeck
            } else {
                let newDeck = Deck(name: newName, languageCode: languageCode)
                modelContext.insert(newDeck)
                updatedDeck = newDeck
            }

            for duplicateDeck in decks where duplicateDeck.name == newName && duplicateDeck !== updatedDeck {
                modelContext.delete(duplicateDeck)
            }

            if selectedDeckName == oldName {
                selectedDeckName = newName
            }

            navigationPath = [.deckDetail(newName)]
        }
    }

    private func resetEditDeckForm() {
        deckBeingEdited = nil
        editedDeckName = ""
        editedDeckLanguageCode = ""
    }

    private func resetAddCardForm() {
        newQuestion = ""
        newAnswer = ""
        newDeckName = selectedDeckName == "Alle" ? "Allgemein" : selectedDeckName
    }

    private func createDemoCards() {
        let demoData: [(deck: String, languageCode: String, questions: [(String, String)])] = [
            ("Mathe", "de-DE", [
                ("Was ist der Unterschied zwischen Umfang und Fläche eines Rechtecks?", "Der Umfang beschreibt die Länge aller Außenseiten zusammen. Die Fläche beschreibt den Inhalt innerhalb des Rechtecks und wird mit Länge mal Breite berechnet."),
                ("Wie funktioniert die Prozentrechnung im Alltag?", "Prozent bedeutet immer ‚von hundert‘. Beim Einkaufen, bei Rabatten oder Zinsen hilft die Prozentrechnung dabei, Anteile und Veränderungen zu berechnen."),
                ("Warum braucht man negative Zahlen?", "Negative Zahlen werden zum Beispiel für Temperaturen unter null Grad, Schulden oder Höhen unter dem Meeresspiegel verwendet."),
                ("Was ist eine Variable in der Mathematik?", "Eine Variable ist ein Platzhalter für eine Zahl. Häufig verwendet man Buchstaben wie x oder y, um unbekannte Werte darzustellen."),
                ("Wie erkennt man eine gerade Zahl?", "Gerade Zahlen lassen sich ohne Rest durch zwei teilen. Beispiele sind 2, 8, 14 oder 120."),
                ("Was beschreibt ein Bruch?", "Ein Bruch beschreibt einen Anteil eines Ganzen. Der obere Wert heißt Zähler, der untere Nenner."),
                ("Warum sind Diagramme wichtig?", "Diagramme helfen dabei, Zahlen und Entwicklungen schneller zu verstehen und visuell darzustellen."),
                ("Was ist eine Gleichung?", "Eine Gleichung zeigt, dass zwei mathematische Ausdrücke gleich groß sind. Ziel ist oft das Finden einer unbekannten Zahl."),
                ("Wie berechnet man den Durchschnitt?", "Alle Werte werden addiert und anschließend durch die Anzahl der Werte geteilt."),
                ("Was bedeutet Quadratwurzel?", "Die Quadratwurzel einer Zahl ist die Zahl, die mit sich selbst multipliziert wieder die Ausgangszahl ergibt.")
            ]),
            ("Englisch", "en-US", [
                ("Wann verwendet man die Zeitform Simple Past?", "Das Simple Past wird für abgeschlossene Handlungen in der Vergangenheit verwendet, oft zusammen mit Zeitangaben wie yesterday oder last week."),
                ("Was ist der Unterschied zwischen some und any?", "Some wird meist in positiven Sätzen verwendet, any häufig in Fragen oder Verneinungen."),
                ("Warum ist englische Aussprache manchmal schwierig?", "Viele Wörter werden anders ausgesprochen als geschrieben. Außerdem gibt es regionale Unterschiede."),
                ("Was bedeutet Present Progressive?", "Mit dem Present Progressive beschreibt man Handlungen, die gerade jetzt passieren."),
                ("Wie bildet man Fragen im Englischen?", "Häufig beginnt die Frage mit einem Hilfsverb wie do, does, did oder is."),
                ("Was bedeutet false friend?", "False friends sind Wörter, die ähnlich aussehen wie deutsche Wörter, aber etwas anderes bedeuten."),
                ("Wann nutzt man much und many?", "Much verwendet man bei nicht zählbaren Dingen, many bei zählbaren Dingen."),
                ("Warum lernt man Vokabeln am besten regelmäßig?", "Kurze Wiederholungen über mehrere Tage helfen dem Gehirn dabei, Inhalte langfristig zu speichern."),
                ("Was ist ein irregular verb?", "Ein irregular verb ist ein unregelmäßiges Verb mit besonderen Vergangenheitsformen."),
                ("Wie verbessert man sein Hörverständnis?", "Durch Serien, Musik, Podcasts oder Gespräche auf Englisch gewöhnt man sich an die Sprache.")
            ]),
            ("Bio", "de-DE", [
                ("Welche Aufgabe hat das Herz?", "Das Herz pumpt Blut durch den Körper und versorgt Organe und Muskeln mit Sauerstoff."),
                ("Warum brauchen Pflanzen Sonnenlicht?", "Pflanzen benötigen Sonnenlicht für die Photosynthese, um Energie herzustellen."),
                ("Was ist eine Zelle?", "Die Zelle ist die kleinste lebende Einheit eines Organismus."),
                ("Welche Aufgabe haben rote Blutkörperchen?", "Sie transportieren Sauerstoff durch den gesamten Körper."),
                ("Warum schlafen Menschen?", "Im Schlaf verarbeitet das Gehirn Informationen und der Körper regeneriert sich."),
                ("Was passiert bei der Verdauung?", "Nahrung wird in kleinere Bestandteile zerlegt, damit der Körper die Nährstoffe aufnehmen kann."),
                ("Wie funktioniert das Immunsystem?", "Das Immunsystem erkennt Krankheitserreger und bekämpft sie mit speziellen Abwehrmechanismen."),
                ("Warum ist Wasser wichtig für den Körper?", "Wasser unterstützt viele Prozesse im Körper und hilft beim Transport von Nährstoffen."),
                ("Was ist DNA?", "DNA enthält die genetischen Informationen eines Lebewesens."),
                ("Warum atmen Menschen?", "Durch das Atmen nimmt der Körper Sauerstoff auf und gibt Kohlendioxid wieder ab.")
            ]),
            ("Kunst", "de-DE", [
                ("Was ist der Unterschied zwischen warmen und kalten Farben?", "Warme Farben wirken energisch und lebendig, kalte Farben eher ruhig und entspannend."),
                ("Warum nutzen Künstler Perspektive?", "Mit Perspektive können Räume und Entfernungen realistischer dargestellt werden."),
                ("Was ist ein Selbstporträt?", "Ein Selbstporträt ist ein Kunstwerk, in dem Künstler sich selbst darstellen."),
                ("Warum sind Skizzen wichtig?", "Skizzen helfen dabei, Ideen schnell festzuhalten und Kompositionen vorzubereiten."),
                ("Was versteht man unter Kontrast?", "Kontraste entstehen durch starke Unterschiede, zum Beispiel hell und dunkel."),
                ("Welche Wirkung haben Farben?", "Farben können Gefühle, Stimmungen und Aufmerksamkeit beeinflussen."),
                ("Was ist moderne Kunst?", "Moderne Kunst umfasst viele unterschiedliche Stilrichtungen und experimentelle Ausdrucksformen."),
                ("Warum arbeiten Künstler mit Licht und Schatten?", "Licht und Schatten erzeugen Tiefe und machen Motive plastischer."),
                ("Was bedeutet abstrakte Kunst?", "Abstrakte Kunst zeigt Formen und Farben ohne realistische Darstellung."),
                ("Warum besuchen Menschen Museen?", "Museen zeigen Kunstwerke, Geschichte und kulturelle Entwicklungen.")
            ]),
            ("Musik", "de-DE", [
                ("Was ist ein Rhythmus?", "Rhythmus beschreibt die zeitliche Struktur von Musik und sorgt für den Takt."),
                ("Welche Aufgabe hat ein Dirigent?", "Ein Dirigent koordiniert Musiker und bestimmt Tempo sowie Dynamik."),
                ("Warum klingt jede Stimme anders?", "Die Stimme wird durch Körperbau, Stimmbänder und Sprechweise beeinflusst."),
                ("Was bedeutet Lautstärke in der Musik?", "Die Lautstärke beschreibt, wie leise oder laut ein Musikstück gespielt wird."),
                ("Was ist eine Melodie?", "Eine Melodie ist eine Folge von Tönen, die als zusammenhängend wahrgenommen wird."),
                ("Warum üben Musiker regelmäßig?", "Regelmäßiges Üben verbessert Technik, Sicherheit und musikalischen Ausdruck."),
                ("Was ist ein Instrumentalstück?", "Ein Instrumentalstück enthält keine gesungenen Texte."),
                ("Wie entstehen unterschiedliche Musikrichtungen?", "Musikrichtungen entwickeln sich durch Kultur, Geschichte und neue Einflüsse."),
                ("Warum wirkt Musik emotional?", "Musik beeinflusst Gefühle durch Rhythmus, Melodie und Erinnerungen."),
                ("Was ist ein Takt?", "Ein Takt ordnet Musik in gleichmäßige rhythmische Abschnitte.")
            ])
        ]

        withAnimation {
            var createdCardCount = 0

            for deck in demoData {
                ensureDeckExists(named: deck.deck, languageCode: deck.languageCode)
                for item in deck.questions {
                    modelContext.insert(Flashcard(question: item.0, answer: item.1, deckName: deck.deck))
                    createdCardCount += 1
                }
            }

            demoCardsCreatedMessage = localizedDemoCardsCreatedMessage(createdCardCount)
        }
    }

    private func deleteAllCards() {
        withAnimation {
            for card in flashcards {
                modelContext.delete(card)
            }

            for deck in decks {
                modelContext.delete(deck)
            }

            selectedDeckName = "Alle"
            navigationPath = []
        }
    }

    private func localizedCardsInDeckCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 Karte im Stapel")
        }

        return String(format: String(localized: "%lld Karten im Stapel"), Int64(count))
    }

    private func localizedDemoCardsCreatedMessage(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 Demo-Karte erstellt.")
        }

        return String(format: String(localized: "%lld Demo-Karten erstellt."), Int64(count))
    }

    private func localizedReviewIntervalLabel(titleKey: String, days: Int) -> String {
        let daysText = String(format: String(localized: "%lld Tage"), Int64(days))
        let title: String
        switch titleKey {
        case "Gewusst":
            title = String(localized: "Gewusst")
        case "Unsicher":
            title = String(localized: "Unsicher")
        default:
            title = String(localized: "Nochmal")
        }

        return String(format: String(localized: "%@: %@"), title, daysText)
    }

    private func localizedDeckCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 Stapel")
        }

        return String(format: String(localized: "%lld Stapel"), Int64(count))
    }
}

private enum NavigationRoute: Hashable {
    case deckDetail(String)
    case deckCards(String)
}

private struct AIDeckSelection: Identifiable {
    let id = UUID()
    let deckName: String
}

private struct OverviewBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.08, green: 0.10, blue: 0.16),
                        Color(red: 0.02, green: 0.02, blue: 0.03)
                    ]
                    : [
                        Color(red: 0.94, green: 0.97, blue: 1.0),
                        Color(.systemBackground)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

private struct DeckOverviewHeroView<LearningAction: View>: View {
    let cardCount: Int
    let dueCards: Int
    @ViewBuilder var learningAction: LearningAction

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lerne mit Teresa")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(dueCards > 0 ? localizedDueMessage(dueCards) : String(localized: "Alles gelernt. Teresa ist bereit für neue Karten."))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .shadow(color: .blue.opacity(0.28), radius: 14, x: 0, y: 8)
            }

            HStack(spacing: 10) {
                LearningMetricView(title: "Heute", value: dueCards, color: .orange, systemImage: "flame.fill")
                LearningMetricView(title: "Gesamt", value: cardCount, color: .blue, systemImage: "rectangle.stack.fill")
            }

            learningAction
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(.regularMaterial)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.orange.opacity(0.18))
                        .frame(width: 120, height: 120)
                        .blur(radius: 18)
                        .offset(x: 28, y: -44)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private func localizedDueMessage(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "Heute wartet 1 Karte auf dich.")
        }

        return String(format: String(localized: "Heute warten %lld Karten auf dich."), Int64(count))
    }
}

private struct LearningMetricView: View {
    let title: String
    let value: Int
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline.bold())

                Text(LocalizedStringKey(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }
}

private enum DeckTileStyle {
    static let palette: [Color] = [.blue, .mint, .orange, .purple, .pink, .green, .cyan]

    static func accent(for index: Int) -> Color {
        palette[index % palette.count]
    }
}

private struct DeckTileView: View {
    let deckName: String
    let cardCount: Int
    let dueCount: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.opacity(0.18))
                        .frame(width: 42, height: 42)

                    Image(systemName: "rectangle.stack.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(accent)
                }

                Spacer()

                if dueCount > 0 {
                    Text("\(dueCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.gradient)
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.35), radius: 8, x: 0, y: 4)
                        .accessibilityLabel(Text(String(format: String(localized: "%lld heute fällig"), Int64(dueCount))))
                }
            }

            Spacer(minLength: 8)

            Text(deckName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(localizedFlashcardCount(cardCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: cardCount == 0 ? 0 : min(Double(dueCount) / Double(max(cardCount, 1)), 1))
                .tint(accent)
                .opacity(cardCount == 0 ? 0.35 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.18), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: accent.opacity(0.10), radius: 18, x: 0, y: 10)
    }

    private func localizedFlashcardCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 Karteikarte")
        }

        return String(format: String(localized: "%lld Karteikarten"), Int64(count))
    }
}

private struct AddDeckTileView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )

            Text("Neuer Stapel")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            Text("Starte ein neues Thema")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.blue.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        }
    }
}

struct DeckLanguage: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }

    static let defaultCode = "de-DE"

    static let all = [
        DeckLanguage(code: "de-DE", name: "Deutsch"),
        DeckLanguage(code: "en-US", name: "Englisch"),
        DeckLanguage(code: "es-ES", name: "Spanisch"),
        DeckLanguage(code: "fr-FR", name: "Französisch"),
        DeckLanguage(code: "it-IT", name: "Italienisch"),
        DeckLanguage(code: "pt-PT", name: "Portugiesisch"),
        DeckLanguage(code: "nl-NL", name: "Niederländisch"),
        DeckLanguage(code: "sv-SE", name: "Schwedisch"),
        DeckLanguage(code: "pl-PL", name: "Polnisch"),
        DeckLanguage(code: "tr-TR", name: "Türkisch"),
        DeckLanguage(code: "ru-RU", name: "Russisch"),
        DeckLanguage(code: "uk-UA", name: "Ukrainisch"),
        DeckLanguage(code: "ar-SA", name: "Arabisch"),
        DeckLanguage(code: "zh-CN", name: "Chinesisch"),
        DeckLanguage(code: "ja-JP", name: "Japanisch"),
        DeckLanguage(code: "ko-KR", name: "Koreanisch")
    ]
}

private struct SpeechSettingsSection: View {
    @AppStorage("speechVoiceIdentifier") private var speechVoiceIdentifier = ""
    @AppStorage("speechRate") private var speechRate = 0.58
    @StateObject private var speechReader = FlashcardSpeechReader()

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                DeckLanguage.all.contains { voice.language.hasPrefix(String($0.code.prefix(2))) }
            }
            .sorted {
                if $0.language == $1.language {
                    return $0.name < $1.name
                }

                return $0.language < $1.language
            }
    }

    var body: some View {
        Section("Audio") {
            Picker("Stimme", selection: $speechVoiceIdentifier) {
                Text("Systemstimme").tag("")

                ForEach(voices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Geschwindigkeit", value: speechRateLabel)

                Slider(value: $speechRate, in: 0.48...0.68, step: 0.01)
            }

            Button {
                if speechReader.isSpeaking {
                    speechReader.stop()
                } else {
                    speechReader.speak(String(localized: "So klingt deine Vorlese-Stimme."), voiceIdentifier: speechVoiceIdentifier, languageCode: DeckLanguage.defaultCode, rate: speechRate)
                }
            } label: {
                Label("Stimme testen", systemImage: speechReader.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
        }
    }

    private var speechRateLabel: String {
        switch speechRate {
        case ..<0.54:
            return String(localized: "Normal")
        case ..<0.62:
            return String(localized: "Schnell")
        default:
            return String(localized: "Sehr schnell")
        }
    }
}

private struct AISubscriptionSettingsSection: View {
    @ObservedObject var subscriptionManager: AISubscriptionManager
    let onUnlockAI: () -> Void
    private let forceUnlockButtonForUITests = ProcessInfo.processInfo.arguments.contains("UITEST_FORCE_AI_UNLOCK_BUTTON")

    var body: some View {
        Section("KI-Funktionen") {
            Label {
                Text(LocalizedStringKey(subscriptionManager.hasActiveSubscription ? "KI-Abo aktiv" : "Kostenloser Modus"))
            } icon: {
                Image(systemName: subscriptionManager.hasActiveSubscription ? "checkmark.seal.fill" : "sparkles")
            }
                .foregroundStyle(subscriptionManager.hasActiveSubscription ? .green : .primary)

            Text(LocalizedStringKey(subscriptionManager.hasActiveSubscription ? "KI-Karten und Antwort-Hilfen sind freigeschaltet." : "Manuelles Lernen bleibt kostenlos. KI-Karten und Antwort-Hilfen benötigen ein Abo."))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !subscriptionManager.hasActiveSubscription || forceUnlockButtonForUITests {
                Button {
                    onUnlockAI()
                } label: {
                    Label("KI freischalten", systemImage: "sparkles")
                }
                .accessibilityIdentifier("unlockAIButton")
            }

            Button("Käufe wiederherstellen") {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            }
            .disabled(subscriptionManager.isLoading)

            if let statusMessage = subscriptionManager.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AIPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var subscriptionManager: AISubscriptionManager

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text("KI-Funktionen freischalten")
                        .font(.title.bold())

                    Text("Die App bleibt kostenlos nutzbar. Das Abo schaltet KI-Karten, einfache Erklärungen, Beispiele, Merksätze und Mini-Quiz frei.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("KI-Karten für deinen aktuellen Stapel erzeugen", systemImage: "rectangle.stack.badge.plus")
                    Label("Antworten einfacher erklären lassen", systemImage: "text.bubble")
                    Label("Beispiele, Merksätze und Mini-Quiz erstellen", systemImage: "lightbulb")
                }
                .font(.subheadline.weight(.medium))

                Spacer()

                if let statusMessage = subscriptionManager.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        if subscriptionManager.monthlyProduct == nil {
                            await subscriptionManager.refresh()
                        } else {
                            await subscriptionManager.purchaseMonthlySubscription()
                        }

                        if subscriptionManager.hasActiveSubscription {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if subscriptionManager.isLoading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(subscriptionManager.monthlyProduct == nil ? String(localized: "KI-Abo laden") : String(format: String(localized: "Für %@ pro Monat aktivieren"), subscriptionManager.monthlyPriceText))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscriptionManager.isLoading)
                .accessibilityIdentifier("aiSubscriptionPurchaseButton")

                Button("Käufe wiederherstellen") {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.hasActiveSubscription {
                            dismiss()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(subscriptionManager.isLoading)
            }
            .padding(24)
            .navigationTitle("KI-Abo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
            .task {
                await subscriptionManager.refresh()
            }
        }
    }
}

final class FlashcardSpeechReader: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voiceIdentifier: String, languageCode: String, rate: Double) {
        speak([FlashcardSpeechSegment(text: text, languageCode: languageCode)], voiceIdentifier: voiceIdentifier, fallbackLanguageCode: languageCode, rate: rate)
    }

    func speak(_ segments: [FlashcardSpeechSegment], voiceIdentifier: String, fallbackLanguageCode: String, rate: Double) {
        let cleanedSegments = segments
            .map {
                FlashcardSpeechSegment(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    languageCode: $0.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackLanguageCode : $0.languageCode
                )
            }
            .filter { !$0.text.isEmpty }

        guard !cleanedSegments.isEmpty else { return }

        stop()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        for segment in cleanedSegments {
            speakSegment(segment, voiceIdentifier: voiceIdentifier, fallbackLanguageCode: fallbackLanguageCode, rate: rate)
        }
    }

    private func speakSegment(_ segment: FlashcardSpeechSegment, voiceIdentifier: String, fallbackLanguageCode: String, rate: Double) {
        let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.voice = selectedVoice(for: voiceIdentifier, languageCode: segment.languageCode.isEmpty ? fallbackLanguageCode : segment.languageCode)
        utterance.rate = Float(min(max(rate, 0.48), 0.68))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        isSpeaking = false
    }

    private func selectedVoice(for identifier: String, languageCode: String) -> AVSpeechSynthesisVoice? {
        let normalizedLanguageCode = languageCode.isEmpty ? DeckLanguage.defaultCode : languageCode
        let languagePrefix = String(normalizedLanguageCode.prefix(2))

        if !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier),
           voice.language.hasPrefix(languagePrefix) {
            return voice
        }

        return AVSpeechSynthesisVoice(language: normalizedLanguageCode)
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(languagePrefix) }
            ?? AVSpeechSynthesisVoice(language: DeckLanguage.defaultCode)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

struct StudyCardView: View {
    @Environment(\.modelContext) private var modelContext
    let cards: [Flashcard]
    let speechLanguageCode: String
    @ObservedObject var subscriptionManager: AISubscriptionManager
    @StateObject private var speechReader = FlashcardSpeechReader()
    @State private var currentCard: Flashcard?
    @State private var isShowingAnswer = false
    @State private var lastResultMessage: String?
    @State private var aiErrorMessage: String?
    @State private var isSimplifyingAnswer = false
    @State private var showingAIPaywall = false
    @State private var reviewedCardCount = 0
    @State private var sessionCardCount = 1
    @State private var cardDragOffset = CGSize.zero
    @State private var aiSourceAnswers: [String: String] = [:]
    @AppStorage("knownReviewDays") private var knownReviewDays = 7
    @AppStorage("unsureReviewDays") private var unsureReviewDays = 1
    @AppStorage("againReviewDays") private var againReviewDays = 0
    @AppStorage("speechVoiceIdentifier") private var speechVoiceIdentifier = ""
    @AppStorage("speechRate") private var speechRate = 0.58

    private let aiService = AIFlashcardService()

    init(cards: [Flashcard], startCard: Flashcard, speechLanguageCode: String = DeckLanguage.defaultCode, subscriptionManager: AISubscriptionManager) {
        self.cards = cards
        self.speechLanguageCode = speechLanguageCode
        self.subscriptionManager = subscriptionManager
        _currentCard = State(initialValue: startCard)
        _sessionCardCount = State(initialValue: max(1, cards.filter { $0.nextReviewDate <= Date() }.count))
    }

    var body: some View {
        VStack(spacing: 14) {
            studyProgressView

            if let card = currentCard {
                studyContent(for: card)
            } else {
                sessionCompleteView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Lernen")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            speechReader.stop()
        }
        .sheet(isPresented: $showingAIPaywall) {
            AIPaywallView(subscriptionManager: subscriptionManager)
        }
        .alert("KI-Funktion nicht verfügbar", isPresented: aiErrorAlertBinding) {
            Button("OK", role: .cancel) {
                aiErrorMessage = nil
            }
        } message: {
            Text(aiErrorMessage ?? "")
        }
    }

    private var aiErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { aiErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    aiErrorMessage = nil
                }
            }
        )
    }

    private var studyProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(localizedStudyProgressText, systemImage: "rectangle.stack.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(localizedRemainingCardCount)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressValue)
                .tint(.blue)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var remainingCardCount: Int {
        max(sessionCardCount - reviewedCardCount, 0)
    }

    private var localizedRemainingCardCount: String {
        if remainingCardCount == 1 {
            return String(localized: "1 Karte übrig")
        }

        return String(format: String(localized: "%lld Karten übrig"), Int64(remainingCardCount))
    }

    private var localizedStudyProgressText: String {
        String(format: String(localized: "%lld von %lld"), Int64(reviewedCardCount), Int64(sessionCardCount))
    }

    private var progressValue: Double {
        guard sessionCardCount > 0 else { return 1 }
        return Double(reviewedCardCount) / Double(sessionCardCount)
    }

    @ViewBuilder
    private func studyContent(for card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.deckName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    speakCurrentSide(of: card)
                } label: {
                    Image(systemName: speechReader.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule())
                .accessibilityLabel(Text(LocalizedStringKey(isShowingAnswer ? "Antwort vorlesen" : "Frage vorlesen")))

                Text(LocalizedStringKey(isShowingAnswer ? "Antwort" : "Frage"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal)

            Text(isShowingAnswer ? card.answer : card.question)
                .font(.system(size: isShowingAnswer ? 26 : 30, weight: .semibold, design: .rounded))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(isShowingAnswer ? 0.44 : 0.5)
                .lineLimit(isShowingAnswer ? 13 : 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: cardDragOffset.width >= 0 ? .topLeading : .topTrailing) {
            if isShowingAnswer && abs(cardDragOffset.width) > 28 {
                Label {
                    Text(LocalizedStringKey(cardDragOffset.width > 0 ? "Gewusst" : "Nochmal"))
                } icon: {
                    Image(systemName: cardDragOffset.width > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(cardDragOffset.width > 0 ? .green : .red)
                    .clipShape(Capsule())
                    .padding(18)
            }
        }
        .padding()
        .layoutPriority(1)
        .contentShape(Rectangle())
        .offset(x: cardDragOffset.width, y: cardDragOffset.height * 0.12)
        .rotationEffect(.degrees(cardDragOffset.width / 24))
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard isShowingAnswer else { return }
                    cardDragOffset = value.translation
                }
                .onEnded { value in
                    handleCardSwipe(value.translation, for: card)
                }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: cardDragOffset)
        .onTapGesture {
            toggleCard()
        }

        if let lastResultMessage {
            Text(lastResultMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36)
                .padding(.horizontal)
        } else {
            Color.clear
                .frame(height: 36)
        }

        answerActionArea(for: card)
    }

    private func answerActionArea(for card: Flashcard) -> some View {
        VStack(spacing: 12) {
            if isShowingAnswer {
                if subscriptionManager.hasActiveSubscription {
                    Menu {
                        ForEach(AnswerTransformOption.allCases) { option in
                            Button {
                                Task {
                                    await transformAnswer(for: card, option: option)
                                }
                            } label: {
                                Label(option.title, systemImage: option.systemImage)
                            }
                        }
                    } label: {
                        if isSimplifyingAnswer {
                            ProgressView()
                                .frame(minWidth: 180, minHeight: 36)
                        } else {
                            HStack(spacing: 8) {
                                Label(AnswerTransformOption.simplify.title, systemImage: AnswerTransformOption.simplify.systemImage)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 36)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isSimplifyingAnswer)
                } else {
                    Button {
                        showingAIPaywall = true
                    } label: {
                        Label("KI freischalten", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                HStack(spacing: 12) {
                    reviewButton(titleKey: "Nochmal", systemImage: "xmark.circle.fill", tint: .red) {
                        markCard(card, result: .again)
                    }

                    reviewButton(titleKey: "Unsicher", systemImage: "questionmark.circle.fill", tint: .yellow) {
                        markCard(card, result: .unsure)
                    }

                    reviewButton(titleKey: "Gewusst", systemImage: "checkmark.circle.fill", tint: .green) {
                        markCard(card, result: .known)
                    }
                }
            } else {
                Color.clear
                    .frame(height: 44)

                Button {
                    toggleCard()
                } label: {
                    Label("Antwort anzeigen", systemImage: "eye")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(height: 128, alignment: .top)
        .padding(.horizontal)
        .padding(.bottom, 18)
    }

    private func reviewButton(titleKey: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(LocalizedStringKey(titleKey))
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var sessionCompleteView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Alles erledigt")
                .font(.largeTitle.bold())

            Text("Für diesen Stapel ist gerade keine weitere Karte fällig.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    private func toggleCard() {
        speechReader.stop()

        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingAnswer.toggle()
            lastResultMessage = nil
            cardDragOffset = .zero
        }
    }

    private func handleCardSwipe(_ translation: CGSize, for card: Flashcard) {
        guard isShowingAnswer else {
            cardDragOffset = .zero
            return
        }

        speechReader.stop()

        let threshold: CGFloat = 120

        if translation.width > threshold {
            cardDragOffset = CGSize(width: 420, height: translation.height * 0.12)
            markCard(card, result: .known)
        } else if translation.width < -threshold {
            cardDragOffset = CGSize(width: -420, height: translation.height * 0.12)
            markCard(card, result: .again)
        } else {
            cardDragOffset = .zero
        }
    }

    private func transformAnswer(for card: Flashcard, option: AnswerTransformOption) async {
        isSimplifyingAnswer = true
        lastResultMessage = nil

        do {
            let sourceAnswerKey = String(describing: card.persistentModelID)
            let sourceAnswer = aiSourceAnswers[sourceAnswerKey] ?? card.answer
            aiSourceAnswers[sourceAnswerKey] = sourceAnswer

            let result = try await aiService.transformAnswer(
                question: card.question,
                answer: sourceAnswer,
                option: option,
                answerLanguageCode: speechLanguageCode,
                appStoreTransactionJWS: subscriptionManager.currentEntitlementJWS
            )
            card.answer = FlashcardTextLimits.limited(result.answer, to: FlashcardTextLimits.answer)
            card.answerSpeechSegments = result.answerSpeechSegments
            card.updatedAt = Date()
            try? modelContext.save()
            lastResultMessage = option.resultMessage
        } catch {
            aiErrorMessage = error.localizedDescription
            lastResultMessage = nil
        }

        isSimplifyingAnswer = false
    }

    private func markCard(_ card: Flashcard, result: ReviewResult) {
        speechReader.stop()

        let now = Date()
        card.updatedAt = now
        card.timesReviewed += 1
        reviewedCardCount = min(reviewedCardCount + 1, sessionCardCount)

        switch result {
        case .known:
            card.timesKnown += 1
            card.nextReviewDate = Calendar.current.date(byAdding: .day, value: knownReviewDays, to: now) ?? now
            lastResultMessage = localizedReviewMessage(prefixKey: "Super", days: knownReviewDays)
        case .unsure:
            card.timesUnsure += 1
            card.nextReviewDate = Calendar.current.date(byAdding: .day, value: unsureReviewDays, to: now) ?? now
            lastResultMessage = localizedReviewMessage(prefixKey: "Okay", days: unsureReviewDays)
        case .again:
            card.timesAgain += 1
            card.nextReviewDate = Calendar.current.date(byAdding: .day, value: againReviewDays, to: now) ?? now
            lastResultMessage = againReviewDays == 0 ? String(localized: "Kein Problem — bleibt heute fällig") : localizedReviewMessage(prefixKey: nil, days: againReviewDays)
        }

        try? modelContext.save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            moveToNextDueCard(after: card)
        }
    }

    private func moveToNextDueCard(after reviewedCard: Flashcard) {
        let now = Date()
        let nextCard = cards
            .filter { $0.persistentModelID != reviewedCard.persistentModelID }
            .filter { $0.nextReviewDate <= now }
            .sorted {
                if $0.nextReviewDate == $1.nextReviewDate {
                    return $0.question < $1.question
                }

                return $0.nextReviewDate < $1.nextReviewDate
            }
            .first

        withAnimation(.spring) {
            currentCard = nextCard
            isShowingAnswer = false
            lastResultMessage = nil
            cardDragOffset = .zero
        }
    }

    private func speakCurrentSide(of card: Flashcard) {
        if speechReader.isSpeaking {
            speechReader.stop()
        } else if isShowingAnswer {
            let segments = card.answerSpeechSegments.isEmpty
                ? [FlashcardSpeechSegment(text: card.answer, languageCode: speechLanguageCode)]
                : card.answerSpeechSegments
            speechReader.speak(segments, voiceIdentifier: speechVoiceIdentifier, fallbackLanguageCode: speechLanguageCode, rate: speechRate)
        } else {
            let segments = card.questionSpeechSegments.isEmpty
                ? [FlashcardSpeechSegment(text: card.question, languageCode: DeckLanguage.defaultCode)]
                : card.questionSpeechSegments
            speechReader.speak(segments, voiceIdentifier: speechVoiceIdentifier, fallbackLanguageCode: DeckLanguage.defaultCode, rate: speechRate)
        }
    }

    private func localizedReviewMessage(prefixKey: String?, days: Int) -> String {
        let daysText = String(format: String(localized: "%lld Tagen"), Int64(days))

        if let prefixKey {
            let prefix = prefixKey == "Super" ? String(localized: "Super") : String(localized: "Okay")
            return String(format: String(localized: "%@ — kommt in %@ wieder"), prefix, daysText)
        }

        return String(format: String(localized: "Kommt in %@ wieder"), daysText)
    }
}

enum ReviewResult {
    case known
    case unsure
    case again
}

struct CloudSyncStatusView: View {
    @State private var status = SyncStatus.checking

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(status.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.headline)

                Text(status.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task {
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        let container = CKContainer(identifier: CloudConfiguration.iCloudContainerIdentifier)

        do {
            let accountStatus = try await container.accountStatus()
            status = SyncStatus(accountStatus: accountStatus)
        } catch {
            status = .unavailable("iCloud konnte gerade nicht geprüft werden. Offline gespeicherte Karten bleiben auf diesem Gerät verfügbar.")
        }
    }
}

private enum SyncStatus {
    case checking
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case unavailable(String)

    init(accountStatus: CKAccountStatus) {
        switch accountStatus {
        case .available:
            self = .available
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .couldNotDetermine:
            self = .couldNotDetermine
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        @unknown default:
            self = .couldNotDetermine
        }
    }

    var title: String {
        switch self {
        case .checking:
            return String(localized: "iCloud wird geprüft")
        case .available:
            return String(localized: "iCloud-Sync aktiv")
        case .noAccount:
            return String(localized: "Keine iCloud-Anmeldung")
        case .restricted:
            return String(localized: "iCloud eingeschränkt")
        case .couldNotDetermine:
            return String(localized: "iCloud-Status unklar")
        case .temporarilyUnavailable:
            return String(localized: "iCloud gerade nicht erreichbar")
        case .unavailable:
            return String(localized: "iCloud nicht verfügbar")
        }
    }

    var message: String {
        switch self {
        case .checking:
            return String(localized: "Die App prüft, ob Karten und Lernstände mit deinem Apple-Account synchronisiert werden können.")
        case .available:
            return String(localized: "Karten und Lernstände werden lokal gespeichert und über deinen Apple-Account synchronisiert.")
        case .noAccount:
            return String(localized: "Melde dich in den iOS-Einstellungen bei iCloud an, damit deine Karten zwischen Geräten synchron bleiben.")
        case .restricted:
            return String(localized: "iCloud ist auf diesem Gerät eingeschränkt. Lokal lernen funktioniert weiterhin.")
        case .couldNotDetermine:
            return String(localized: "Der iCloud-Status konnte nicht eindeutig bestimmt werden. Offline gespeicherte Karten bleiben verfügbar.")
        case .temporarilyUnavailable:
            return String(localized: "Die App speichert weiter lokal und synchronisiert später, sobald iCloud wieder erreichbar ist.")
        case .unavailable(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            return "icloud"
        case .available:
            return "icloud.fill"
        case .temporarilyUnavailable:
            return "icloud.slash"
        default:
            return "exclamationmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return .blue
        case .checking, .temporarilyUnavailable:
            return .secondary
        default:
            return .orange
        }
    }
}

extension Flashcard {
    var reviewStatusText: String {
        if nextReviewDate <= Date() {
            return String(localized: "Heute fällig")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = .autoupdatingCurrent
        return String(localized: "Wiederholung ") + formatter.localizedString(for: nextReviewDate, relativeTo: Date())
    }
}

#Preview {
    let container = try! ModelContainer(for: Flashcard.self, Deck.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext

    let demoCards: [Flashcard] = [
        // MARK: Mathe
        Flashcard(question: "Was ist der Unterschied zwischen Umfang und Fläche eines Rechtecks?", answer: "Der Umfang beschreibt die Länge aller Außenseiten zusammen. Die Fläche beschreibt den Inhalt innerhalb des Rechtecks und wird mit Länge mal Breite berechnet.", deckName: "Mathe"),
        Flashcard(question: "Wie funktioniert die Prozentrechnung im Alltag?", answer: "Prozent bedeutet immer ‚von hundert‘. Beim Einkaufen, bei Rabatten oder Zinsen hilft die Prozentrechnung dabei, Anteile und Veränderungen zu berechnen.", deckName: "Mathe"),
        Flashcard(question: "Warum braucht man negative Zahlen?", answer: "Negative Zahlen werden zum Beispiel für Temperaturen unter null Grad, Schulden oder Höhen unter dem Meeresspiegel verwendet.", deckName: "Mathe"),
        Flashcard(question: "Was ist eine Variable in der Mathematik?", answer: "Eine Variable ist ein Platzhalter für eine Zahl. Häufig verwendet man Buchstaben wie x oder y, um unbekannte Werte darzustellen.", deckName: "Mathe"),
        Flashcard(question: "Wie erkennt man eine gerade Zahl?", answer: "Gerade Zahlen lassen sich ohne Rest durch zwei teilen. Beispiele sind 2, 8, 14 oder 120.", deckName: "Mathe"),
        Flashcard(question: "Was beschreibt ein Bruch?", answer: "Ein Bruch beschreibt einen Anteil eines Ganzen. Der obere Wert heißt Zähler, der untere Nenner.", deckName: "Mathe"),
        Flashcard(question: "Warum sind Diagramme wichtig?", answer: "Diagramme helfen dabei, Zahlen und Entwicklungen schneller zu verstehen und visuell darzustellen.", deckName: "Mathe"),
        Flashcard(question: "Was ist eine Gleichung?", answer: "Eine Gleichung zeigt, dass zwei mathematische Ausdrücke gleich groß sind. Ziel ist oft das Finden einer unbekannten Zahl.", deckName: "Mathe"),
        Flashcard(question: "Wie berechnet man den Durchschnitt?", answer: "Alle Werte werden addiert und anschließend durch die Anzahl der Werte geteilt.", deckName: "Mathe"),
        Flashcard(question: "Was bedeutet Quadratwurzel?", answer: "Die Quadratwurzel einer Zahl ist die Zahl, die mit sich selbst multipliziert wieder die Ausgangszahl ergibt.", deckName: "Mathe"),

        // MARK: Englisch
        Flashcard(question: "Wann verwendet man die Zeitform Simple Past?", answer: "Das Simple Past wird für abgeschlossene Handlungen in der Vergangenheit verwendet, oft zusammen mit Zeitangaben wie yesterday oder last week.", deckName: "Englisch"),
        Flashcard(question: "Was ist der Unterschied zwischen some und any?", answer: "Some wird meist in positiven Sätzen verwendet, any häufig in Fragen oder Verneinungen.", deckName: "Englisch"),
        Flashcard(question: "Warum ist englische Aussprache manchmal schwierig?", answer: "Viele Wörter werden anders ausgesprochen als geschrieben. Außerdem gibt es regionale Unterschiede.", deckName: "Englisch"),
        Flashcard(question: "Was bedeutet Present Progressive?", answer: "Mit dem Present Progressive beschreibt man Handlungen, die gerade jetzt passieren.", deckName: "Englisch"),
        Flashcard(question: "Wie bildet man Fragen im Englischen?", answer: "Häufig beginnt die Frage mit einem Hilfsverb wie do, does, did oder is.", deckName: "Englisch"),
        Flashcard(question: "Was bedeutet false friend?", answer: "False friends sind Wörter, die ähnlich aussehen wie deutsche Wörter, aber etwas anderes bedeuten.", deckName: "Englisch"),
        Flashcard(question: "Wann nutzt man much und many?", answer: "Much verwendet man bei nicht zählbaren Dingen, many bei zählbaren Dingen.", deckName: "Englisch"),
        Flashcard(question: "Warum lernt man Vokabeln am besten regelmäßig?", answer: "Kurze Wiederholungen über mehrere Tage helfen dem Gehirn dabei, Inhalte langfristig zu speichern.", deckName: "Englisch"),
        Flashcard(question: "Was ist ein irregular verb?", answer: "Ein irregular verb ist ein unregelmäßiges Verb mit besonderen Vergangenheitsformen.", deckName: "Englisch"),
        Flashcard(question: "Wie verbessert man sein Hörverständnis?", answer: "Durch Serien, Musik, Podcasts oder Gespräche auf Englisch gewöhnt man sich an die Sprache.", deckName: "Englisch"),

        // MARK: Bio
        Flashcard(question: "Welche Aufgabe hat das Herz?", answer: "Das Herz pumpt Blut durch den Körper und versorgt Organe und Muskeln mit Sauerstoff.", deckName: "Bio"),
        Flashcard(question: "Warum brauchen Pflanzen Sonnenlicht?", answer: "Pflanzen benötigen Sonnenlicht für die Photosynthese, um Energie herzustellen.", deckName: "Bio"),
        Flashcard(question: "Was ist eine Zelle?", answer: "Die Zelle ist die kleinste lebende Einheit eines Organismus.", deckName: "Bio"),
        Flashcard(question: "Welche Aufgabe haben rote Blutkörperchen?", answer: "Sie transportieren Sauerstoff durch den gesamten Körper.", deckName: "Bio"),
        Flashcard(question: "Warum schlafen Menschen?", answer: "Im Schlaf verarbeitet das Gehirn Informationen und der Körper regeneriert sich.", deckName: "Bio"),
        Flashcard(question: "Was passiert bei der Verdauung?", answer: "Nahrung wird in kleinere Bestandteile zerlegt, damit der Körper die Nährstoffe aufnehmen kann.", deckName: "Bio"),
        Flashcard(question: "Wie funktioniert das Immunsystem?", answer: "Das Immunsystem erkennt Krankheitserreger und bekämpft sie mit speziellen Abwehrmechanismen.", deckName: "Bio"),
        Flashcard(question: "Warum ist Wasser wichtig für den Körper?", answer: "Wasser unterstützt viele Prozesse im Körper und hilft beim Transport von Nährstoffen.", deckName: "Bio"),
        Flashcard(question: "Was ist DNA?", answer: "DNA enthält die genetischen Informationen eines Lebewesens.", deckName: "Bio"),
        Flashcard(question: "Warum atmen Menschen?", answer: "Durch das Atmen nimmt der Körper Sauerstoff auf und gibt Kohlendioxid wieder ab.", deckName: "Bio"),

        // MARK: Kunst
        Flashcard(question: "Was ist der Unterschied zwischen warmen und kalten Farben?", answer: "Warme Farben wirken energisch und lebendig, kalte Farben eher ruhig und entspannend.", deckName: "Kunst"),
        Flashcard(question: "Warum nutzen Künstler Perspektive?", answer: "Mit Perspektive können Räume und Entfernungen realistischer dargestellt werden.", deckName: "Kunst"),
        Flashcard(question: "Was ist ein Selbstporträt?", answer: "Ein Selbstporträt ist ein Kunstwerk, in dem Künstler sich selbst darstellen.", deckName: "Kunst"),
        Flashcard(question: "Warum sind Skizzen wichtig?", answer: "Skizzen helfen dabei, Ideen schnell festzuhalten und Kompositionen vorzubereiten.", deckName: "Kunst"),
        Flashcard(question: "Was versteht man unter Kontrast?", answer: "Kontraste entstehen durch starke Unterschiede, zum Beispiel hell und dunkel.", deckName: "Kunst"),
        Flashcard(question: "Welche Wirkung haben Farben?", answer: "Farben können Gefühle, Stimmungen und Aufmerksamkeit beeinflussen.", deckName: "Kunst"),
        Flashcard(question: "Was ist moderne Kunst?", answer: "Moderne Kunst umfasst viele unterschiedliche Stilrichtungen und experimentelle Ausdrucksformen.", deckName: "Kunst"),
        Flashcard(question: "Warum arbeiten Künstler mit Licht und Schatten?", answer: "Licht und Schatten erzeugen Tiefe und machen Motive plastischer.", deckName: "Kunst"),
        Flashcard(question: "Was bedeutet abstrakte Kunst?", answer: "Abstrakte Kunst zeigt Formen und Farben ohne realistische Darstellung.", deckName: "Kunst"),
        Flashcard(question: "Warum besuchen Menschen Museen?", answer: "Museen zeigen Kunstwerke, Geschichte und kulturelle Entwicklungen.", deckName: "Kunst"),

        // MARK: Musik
        Flashcard(question: "Was ist ein Rhythmus?", answer: "Rhythmus beschreibt die zeitliche Struktur von Musik und sorgt für den Takt.", deckName: "Musik"),
        Flashcard(question: "Welche Aufgabe hat ein Dirigent?", answer: "Ein Dirigent koordiniert Musiker und bestimmt Tempo sowie Dynamik.", deckName: "Musik"),
        Flashcard(question: "Warum klingt jede Stimme anders?", answer: "Die Stimme wird durch Körperbau, Stimmbänder und Sprechweise beeinflusst.", deckName: "Musik"),
        Flashcard(question: "Was bedeutet Lautstärke in der Musik?", answer: "Die Lautstärke beschreibt, wie leise oder laut ein Musikstück gespielt wird.", deckName: "Musik"),
        Flashcard(question: "Was ist eine Melodie?", answer: "Eine Melodie ist eine Folge von Tönen, die als zusammenhängend wahrgenommen wird.", deckName: "Musik"),
        Flashcard(question: "Warum üben Musiker regelmäßig?", answer: "Regelmäßiges Üben verbessert Technik, Sicherheit und musikalischen Ausdruck.", deckName: "Musik"),
        Flashcard(question: "Was ist ein Instrumentalstück?", answer: "Ein Instrumentalstück enthält keine gesungenen Texte.", deckName: "Musik"),
        Flashcard(question: "Wie entstehen unterschiedliche Musikrichtungen?", answer: "Musikrichtungen entwickeln sich durch Kultur, Geschichte und neue Einflüsse.", deckName: "Musik"),
        Flashcard(question: "Warum wirkt Musik emotional?", answer: "Musik beeinflusst Gefühle durch Rhythmus, Melodie und Erinnerungen.", deckName: "Musik"),
        Flashcard(question: "Was ist ein Takt?", answer: "Ein Takt ordnet Musik in gleichmäßige rhythmische Abschnitte.", deckName: "Musik")
    ]

    for card in demoCards {
        context.insert(card)
    }

    return ContentView()
        .modelContainer(container)
}

struct IntroView: View {
    let onFinished: () -> Void
    @State private var cardSpread = false
    @State private var cardFloat = false
    @State private var titleScale = 0.92
    @State private var titleOpacity = 0.0
    @State private var glowScale = 0.82
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.07, green: 0.11, blue: 0.22),
                    Color(red: 0.12, green: 0.18, blue: 0.42),
                    Color(red: 0.52, green: 0.24, blue: 0.78)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.cyan.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 38)
                .offset(x: -140, y: -280)
                .scaleEffect(glowScale)

            Circle()
                .fill(.orange.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 34)
                .offset(x: 160, y: 250)
                .scaleEffect(cardFloat ? 1.18 : 0.9)

            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("Study Cards")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .scaleEffect(titleScale)
                        .opacity(titleOpacity)

                    Text("Learn with Teresa")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .opacity(titleOpacity)
                }

                ZStack(alignment: .center) {
                    IntroLearningCard(
                        title: "Merken",
                        subtitle: "Wiederholen",
                        systemImage: "brain.head.profile",
                        tint: .orange
                    )
                    .rotationEffect(.degrees(cardSpread ? -12 : -2))
                    .offset(x: cardSpread ? -76 : -16, y: cardSpread ? 22 : 6)
                    .scaleEffect(0.92)

                    IntroLearningCard(
                        title: "Verstehen",
                        subtitle: "Schritt für Schritt",
                        systemImage: "lightbulb.fill",
                        tint: .mint
                    )
                    .rotationEffect(.degrees(cardSpread ? 11 : 2))
                    .offset(x: cardSpread ? 76 : 16, y: cardSpread ? 18 : 6)
                    .scaleEffect(0.92)

                    RoundedRectangle(cornerRadius: 30)
                        .fill(.white)
                        .frame(width: 210, height: 254)
                        .shadow(color: .black.opacity(0.28), radius: 28, x: 0, y: 18)
                        .overlay {
                            VStack(spacing: 18) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )

                                Text("Ready?")
                                    .font(.system(size: 30, weight: .black, design: .rounded))
                                    .foregroundStyle(.black)
                                    .lineLimit(1)

                                Text("Tap. Flip. Learn.")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black.opacity(0.68))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                ProgressView(value: progress)
                                    .tint(.purple)
                                    .frame(width: 130)
                            }
                            .padding(20)
                        }
                        .rotationEffect(.degrees(cardFloat ? 2.5 : -2.5))
                        .offset(y: cardFloat ? -8 : 4)
                }
                .frame(height: 290)

                Text("Deine Karten. Dein Tempo.")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                titleScale = 1.0
                titleOpacity = 1.0
                cardSpread = true
            }

            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                cardFloat = true
                glowScale = 1.15
            }

            withAnimation(.easeInOut(duration: 1.8)) {
                progress = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                onFinished()
            }
        }
    }
}

private struct IntroLearningCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 26)
            .fill(.white.opacity(0.88))
            .frame(width: 170, height: 220)
            .overlay {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 42, height: 42)
                        .background(tint.opacity(0.16), in: Circle())

                    Spacer()

                    Text(LocalizedStringKey(title))
                        .font(.headline.bold())
                        .foregroundStyle(.black)

                    Text(LocalizedStringKey(subtitle))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 12)
    }
}
