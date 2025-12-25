//
//  Item.swift
//  BrewDeck
//
//  Created by Viktor Sokolov on 21/12/2025.
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
