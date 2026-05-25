//
//  Item.swift
//  Flashcards
//
//  Created by Jens Wolf on 25.05.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
