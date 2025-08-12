//
//  ChatMessage.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//
import Foundation

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let timestamp: Date
}
