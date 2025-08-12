//
//  Persona.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//

import Foundation

struct Persona: Codable, Equatable {
    var id: String
    var name: String
    var basePrompt: String   // 人格設定（DNA）
}
