//
//  ChatViewModel.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//

//  ChatViewModel.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//
import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class ChatViewModel: ObservableObject {
    // UI 狀態
    @Published var isTyping: Bool = false
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""

    // （可選）人格設定：仍保留你原本的欄位與 applyPersona()
    @Published var personaName: String = "Perper"
    @Published var personaPrompt: String =
        "你是喜歡戶外、愛小貓咪, 有三隻貓貓的 愛看科幻,各種懸疑 古裝 美國電視劇的有點兇兇的女孩, 要本色出演 不要太有禮貌, 要像真的女生那樣有自己個性跟人交談."

    /// 目標聊天室。若外部沒傳，VM 會自動嘗試使用 pinned AI chat，找不到就呼叫 startUserAIChat 新建。
    private(set) var chatId: String?

    private var listener: ListenerRegistration?

    // MARK: - 初始化
    /// 方便從聊天列表帶入 chatId
    init(chatId: String? = nil) {
        self.chatId = chatId
        Task { await start() }
    }

    deinit { listener?.remove() }

    // MARK: - 生命週期
    func start() async {
        // 1) 確保登入（匿名）
        if Auth.auth().currentUser == nil {
            _ = try? await Auth.auth().signInAnonymously()
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // 2) 確保有 chatId：優先讀 pinned；沒有就建立 user-ai 聊天
        if chatId == nil {
            let db = Firestore.firestore()
            do {
                let userSnap = try await db.collection("users").document(uid).getDocument()
                if let sys = userSnap.data()?["system"] as? [String: Any],
                   let pinned = sys["pinnedAIChatId"] as? String,
                   !pinned.isEmpty {
                    self.chatId = pinned
                } else {
                    // 沒有 pinned 時，呼叫後端建立一個
                    let res = try await Functions.functions(region: "us-central1")
                        .httpsCallable("startUserAIChat").call([:])
                    if let dict = res.data as? [String: Any],
                       let cid = dict["chatId"] as? String {
                        self.chatId = cid
                    }
                }
            } catch {
                print("ensure chatId error:", error.localizedDescription)
            }
        }

        // 3) 監聽訊息
        attachListener()
    }

    private func attachListener() {
        listener?.remove()
        guard let chatId else { return }
        let db = Firestore.firestore()
        listener = db.collection("chats").document(chatId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err = err {
                    print("listen error:", err.localizedDescription)
                    return
                }
                let docs = snap?.documents ?? []
                let mapped = docs.compactMap(ChatMessage.init(doc:))
                self.messages = mapped

                // 簡單 typing 指示：最後一則若是 user，就顯示「對方正在輸入…」
                if let last = mapped.last {
                    self.isTyping = last.isUser
                } else {
                    self.isTyping = false
                }
            }
    }

    // MARK: - 動作
    func send() async {
        let textTrim = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textTrim.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let chatId else { return }

        input = ""
        isTyping = true

        let db = Firestore.firestore()
        let now = Timestamp(date: Date())
        do {
            try await db.collection("chats").document(chatId)
                .collection("messages")
                .addDocument(data: [
                    "role": "user",
                    "senderId": uid,
                    "text": textTrim,
                    "createdAt": now,
                    "status": "sent"
                ])
            // 讓排序立即更新（後端回覆時也會再更新）
            try await db.collection("chats").document(chatId)
                .setData(["lastMessageAt": now], merge: true)
        } catch {
            print("send error:", error.localizedDescription)
            isTyping = false
        }
    }

    /// 仍可用來改 persona（後端 upsertPersona 你已完成）
    func applyPersona() async {
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("upsertPersona")
                .call(["mbti": "ENFP", "basePrompt": personaPrompt])
        } catch {
            print("upsert persona error:", error.localizedDescription)
        }
    }

    // MARK: -（可選）供外部指定聊天，之後重新監聽
    func setChatId(_ id: String) {
        chatId = id
        attachListener()
    }
}

