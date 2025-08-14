//
//  Item.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
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
