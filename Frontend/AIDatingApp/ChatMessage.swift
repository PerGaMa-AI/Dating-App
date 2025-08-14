//
//  ChatMessage.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//
import Foundation
import FirebaseFirestore

struct ChatMessage: Identifiable, Hashable, Codable {
    // 以 Firestore 文件 ID 當主鍵（穩定、不會重生）
    let id: String
    let text: String
    let isUser: Bool
    /// Firestore 的 Timestamp 轉 Date；AI/使用者訊息都會寫這欄位
    let createdAt: Date?

    // 主要建構子（程式內部也可用）
    init(id: String, text: String, isUser: Bool, createdAt: Date?) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.createdAt = createdAt
    }

    // 從 Firestore DocumentSnapshot 轉模型
    init?(doc: DocumentSnapshot) {
        let data = doc.data() ?? [:]
        guard let role = data["role"] as? String,
              let text = data["text"] as? String else {
            return nil
        }
        self.id = doc.documentID
        self.text = text
        self.isUser = (role == "user")
        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = nil
        }
    }

    // 若你還有舊程式用到 `timestamp` 命名，提供相容別名
    var timestamp: Date { createdAt ?? Date() }
}
