//
//  MemoryStore.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//

import Foundation

final class MemoryStore: ObservableObject {
    // 以 conversationId 做區分；MVP 先用單一會話
    @Published var recentMessages: [ChatMessage] = []  // 最近 N 條做上下文
    @Published var persona: Persona = .init(
        id: "p1",
        name: "小愛",
        basePrompt: "你是喜歡戶外、愛狗、愛看宮崎駿的溫柔女孩，說話幽默。"
    )

    func append(_ msg: ChatMessage, keepLast n: Int = 16) {
        recentMessages.append(msg)
        if recentMessages.count > n { recentMessages.removeFirst(recentMessages.count - n) }
    }

    func reset() {
        recentMessages.removeAll()
    }
}
