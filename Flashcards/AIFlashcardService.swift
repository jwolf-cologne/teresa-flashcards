//
//  AIFlashcardService.swift
//  Flashcards
//
//  Created by Jens Wolf on 25.05.26.
//

import Foundation

struct AIGeneratedFlashcard: Identifiable, Codable {
    var id = UUID()
    var question: String
    var answer: String
    var questionSpeechSegments: [FlashcardSpeechSegment]
    var answerSpeechSegments: [FlashcardSpeechSegment]
    var deckName: String?

    enum CodingKeys: String, CodingKey {
        case question
        case answer
        case questionSpeechSegments
        case answerSpeechSegments
        case deckName
    }
}

struct AIAnswerTransformResult {
    let answer: String
    let answerSpeechSegments: [FlashcardSpeechSegment]
}

struct AIFlashcardService {
    func generateCards(
        endpoint: String = CloudConfiguration.supabaseAIEndpoint,
        topic: String,
        difficultyLevel: String,
        count: Int,
        deckName: String,
        answerLanguageCode: String = "de-DE",
        appStoreTransactionJWS: String?
    ) async throws -> [AIGeneratedFlashcard] {
        guard let appStoreTransactionJWS, !appStoreTransactionJWS.isEmpty else {
            throw AIFlashcardError.subscriptionRequired
        }

        let request = GenerateCardsRequest(
            topic: topic,
            difficultyLevel: difficultyLevel,
            count: count,
            deckName: deckName,
            language: "de",
            answerLanguageCode: answerLanguageCode,
            appStoreTransactionJWS: appStoreTransactionJWS
        )
        let response: GenerateCardsResponse = try await post(endpoint: endpoint, body: request)
        return response.cards.map { card in
            let question = card.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = card.answer.trimmingCharacters(in: .whitespacesAndNewlines)

            return AIGeneratedFlashcard(
                question: question,
                answer: answer,
                questionSpeechSegments: Self.cleanedSegments(card.questionSpeechSegments, matching: question),
                answerSpeechSegments: Self.cleanedSegments(card.answerSpeechSegments, matching: answer),
                deckName: card.deckName?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        .filter { !$0.question.isEmpty && !$0.answer.isEmpty }
    }

    func transformAnswer(
        endpoint: String = CloudConfiguration.supabaseAIEndpoint,
        question: String,
        answer: String,
        option: AnswerTransformOption,
        answerLanguageCode: String = "de-DE",
        appStoreTransactionJWS: String?
    ) async throws -> AIAnswerTransformResult {
        guard let appStoreTransactionJWS, !appStoreTransactionJWS.isEmpty else {
            throw AIFlashcardError.subscriptionRequired
        }

        let request = TransformAnswerRequest(question: question, answer: answer, mode: option.rawValue, language: "de", answerLanguageCode: answerLanguageCode, appStoreTransactionJWS: appStoreTransactionJWS)
        let response: SimplifyAnswerResponse = try await post(endpoint: endpoint, body: request)
        let transformedAnswer = response.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        if transformedAnswer.isEmpty {
            throw AIFlashcardError.emptyResponse
        }

        return AIAnswerTransformResult(answer: transformedAnswer, answerSpeechSegments: Self.cleanedSegments(response.answerSpeechSegments, matching: transformedAnswer))
    }

    func simplifyAnswer(endpoint: String = CloudConfiguration.supabaseAIEndpoint, question: String, answer: String) async throws -> String {
        try await transformAnswer(endpoint: endpoint, question: question, answer: answer, option: .simplify, appStoreTransactionJWS: nil).answer
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        endpoint: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        guard let url = Self.normalizedEndpointURL(from: endpoint) else {
            throw AIFlashcardError.missingEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIFlashcardError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = Self.errorMessage(from: data)
            throw AIFlashcardError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw AIFlashcardError.decodingFailed
        }
    }

    private static func normalizedEndpointURL(from endpoint: String) -> URL? {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEndpoint.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedEndpoint),
           let scheme = url.scheme,
           ["https", "http"].contains(scheme.lowercased()) {
            return url
        }

        let host = trimmedEndpoint.contains(".")
            ? trimmedEndpoint
            : "\(trimmedEndpoint).supabase.co"

        return URL(string: "https://\(host)/functions/v1/flashcards-ai")
    }

    private static func errorMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(AIErrorResponse.self, from: data) {
            return payload.error.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedSegments(_ segments: [FlashcardSpeechSegment]?, matching text: String? = nil) -> [FlashcardSpeechSegment] {
        let cleaned = (segments ?? [])
            .map {
                FlashcardSpeechSegment(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    languageCode: $0.languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty && !$0.languageCode.isEmpty }

        guard let text else {
            return cleaned
        }

        let normalizedSegmentText = cleaned.map(\.text).joined(separator: " ").normalizedForSpeechSegmentComparison
        let normalizedText = text.normalizedForSpeechSegmentComparison
        return normalizedSegmentText == normalizedText ? cleaned : []
    }
}

private struct AIErrorResponse: Decodable {
    let error: String
}

private extension String {
    var normalizedForSpeechSegmentComparison: String {
        components(separatedBy: .whitespacesAndNewlines).joined(separator: " ")
    }
}

enum AnswerTransformOption: String, CaseIterable, Identifiable {
    case simplify = "simplify"
    case example = "example"
    case mnemonic = "mnemonic"
    case miniQuiz = "mini_quiz"
    case childFriendly = "child_friendly"
    case examAnswer = "exam_answer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplify:
            return String(localized: "Einfacher erklären")
        case .example:
            return String(localized: "Beispiel geben")
        case .mnemonic:
            return String(localized: "Merksatz erzeugen")
        case .miniQuiz:
            return String(localized: "Mini-Quiz stellen")
        case .childFriendly:
            return String(localized: "Kindgerechte Erklärung")
        case .examAnswer:
            return String(localized: "Prüfungsantwort")
        }
    }

    var systemImage: String {
        switch self {
        case .simplify:
            return "sparkles"
        case .example:
            return "lightbulb"
        case .mnemonic:
            return "brain.head.profile"
        case .miniQuiz:
            return "questionmark.circle"
        case .childFriendly:
            return "figure.child"
        case .examAnswer:
            return "graduationcap"
        }
    }

    var resultMessage: String {
        switch self {
        case .simplify:
            return String(localized: "Einfacher erklärt")
        case .example:
            return String(localized: "Beispiel ergänzt")
        case .mnemonic:
            return String(localized: "Merksatz erzeugt")
        case .miniQuiz:
            return String(localized: "Mini-Quiz erzeugt")
        case .childFriendly:
            return String(localized: "Kindgerecht erklärt")
        case .examAnswer:
            return String(localized: "Prüfungsantwort erzeugt")
        }
    }
}

private struct GenerateCardsRequest: Encodable {
    let action = "generate_cards"
    let topic: String
    let difficultyLevel: String
    let count: Int
    let deckName: String
    let language: String
    let answerLanguageCode: String
    let appStoreTransactionJWS: String
}

private struct GenerateCardsResponse: Decodable {
    let cards: [GeneratedCardPayload]
}

private struct GeneratedCardPayload: Decodable {
    let question: String
    let answer: String
    let questionSpeechSegments: [FlashcardSpeechSegment]?
    let answerSpeechSegments: [FlashcardSpeechSegment]?
    let deckName: String?
}

private struct TransformAnswerRequest: Encodable {
    let action = "simplify_answer"
    let question: String
    let answer: String
    let mode: String
    let language: String
    let answerLanguageCode: String
    let appStoreTransactionJWS: String
}

private struct SimplifyAnswerResponse: Decodable {
    let answer: String
    let answerSpeechSegments: [FlashcardSpeechSegment]?
}

enum AIFlashcardError: LocalizedError {
    case missingEndpoint
    case subscriptionRequired
    case invalidResponse
    case decodingFailed
    case emptyResponse
    case serverError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return String(localized: "Der KI-Endpunkt ist nicht konfiguriert.")
        case .subscriptionRequired:
            return String(localized: "Für KI-Funktionen ist ein aktives Abo erforderlich.")
        case .invalidResponse:
            return String(localized: "Die KI-Antwort konnte nicht gelesen werden.")
        case .decodingFailed:
            return String(localized: "Die KI hat kein passendes Kartenformat zurückgegeben.")
        case .emptyResponse:
            return String(localized: "Die KI hat keine nutzbare Antwort geliefert.")
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                if statusCode == 402 || statusCode == 403 {
                    return message
                }

                return String(localized: "Der KI-Endpunkt meldet Fehler \(statusCode): \(message)")
            }

            return String(localized: "Der KI-Endpunkt meldet Fehler \(statusCode).")
        }
    }
}
