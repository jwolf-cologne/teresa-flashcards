//
//  Item.swift
//  Flashcards
//
//  Created by Jens Wolf on 25.05.26.
//

import Foundation
import SwiftData

enum FlashcardTextLimits {
    static let question = 180
    static let answer = 360

    static func limited(_ text: String, to maxLength: Int) -> String {
        String(text.prefix(maxLength))
    }
}

struct FlashcardSpeechSegment: Codable, Hashable {
    var text: String
    var languageCode: String
}

@Model
final class Flashcard {
    var question: String = ""
    var answer: String = ""
    var questionSpeechSegmentsJSON: String = ""
    var answerSpeechSegmentsJSON: String = ""
    var deckName: String = "Allgemein"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var nextReviewDate: Date = Date()
    var timesReviewed: Int = 0
    var timesKnown: Int = 0
    var timesUnsure: Int = 0
    var timesAgain: Int = 0

    init(question: String, answer: String, deckName: String = "Allgemein", questionSpeechSegments: [FlashcardSpeechSegment] = [], answerSpeechSegments: [FlashcardSpeechSegment] = []) {
        self.question = question
        self.answer = answer
        self.questionSpeechSegmentsJSON = Self.encodeSpeechSegments(questionSpeechSegments)
        self.answerSpeechSegmentsJSON = Self.encodeSpeechSegments(answerSpeechSegments)
        self.deckName = deckName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.nextReviewDate = Date()
        self.timesReviewed = 0
        self.timesKnown = 0
        self.timesUnsure = 0
        self.timesAgain = 0
    }

    var questionSpeechSegments: [FlashcardSpeechSegment] {
        get {
            Self.decodeSpeechSegments(questionSpeechSegmentsJSON)
        }
        set {
            questionSpeechSegmentsJSON = Self.encodeSpeechSegments(newValue)
        }
    }

    var answerSpeechSegments: [FlashcardSpeechSegment] {
        get {
            Self.decodeSpeechSegments(answerSpeechSegmentsJSON)
        }
        set {
            answerSpeechSegmentsJSON = Self.encodeSpeechSegments(newValue)
        }
    }

    private static func decodeSpeechSegments(_ json: String) -> [FlashcardSpeechSegment] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let segments = try? JSONDecoder().decode([FlashcardSpeechSegment].self, from: data) else {
            return []
        }

        return segments
    }

    private static func encodeSpeechSegments(_ segments: [FlashcardSpeechSegment]) -> String {
        guard !segments.isEmpty,
              let data = try? JSONEncoder().encode(segments),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }

        return json
    }
}

@Model
final class Deck {
    var name: String = ""
    var languageCode: String = "de-DE"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, languageCode: String = "de-DE") {
        self.name = name
        self.languageCode = languageCode
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
