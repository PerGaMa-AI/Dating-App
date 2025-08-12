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

@MainActor
class ChatViewModel: ObservableObject {
    @Published var isTyping: Bool = false
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var personaName: String = "希希per"
    @Published var personaPrompt: String = "你是喜歡戶外、愛小貓咪, 有三隻貓貓的 愛看科幻,各種懸疑 古裝 美國電視劇的有點兇兇的女孩, 要本色出演 不要太有禮貌, 要像真的女生那樣有自己個性跟人交談."

    let userId = "u_demo_001"
    let memory = MemoryStore()

    // NEW: 用來取消進行中的串流
    private var currentTask: Task<Void, Never>?

    // NEW: 取消串流（例如使用者按「停止生成」）
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isTyping = false
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 使用者訊息
        let userMsg = ChatMessage(isUser: true, text: text, timestamp: Date())
        messages.append(userMsg)
        memory.append(userMsg)
        input = ""

        isTyping = true

        // 取消前一個任務（若存在）
        currentTask?.cancel()

        // 不預先放空白 AI 氣泡！等第一個 delta 再放。
        currentTask = Task { [weak self] in
            guard let self else { return }
            var botIndex: Int? = nil
            var accumulated = ""

            do {
                // 串流：等第一個 delta 才新增 AI 訊息
                for try await delta in ChatAPIStream.streamMessage(
                    userId: self.userId,
                    content: text,
                    systemPrompt: self.personaPrompt // 若想用固定 system，可改成常量
                ) {
                    try Task.checkCancellation()

                    // 第一次收到字：建立 AI 氣泡
                    if botIndex == nil {
                        let first = ChatMessage(isUser: false, text: "", timestamp: Date())
                        self.messages.append(first)
                        botIndex = self.messages.count - 1
                    }

                    accumulated += delta
                    if let idx = botIndex {
                        self.messages[idx] = ChatMessage(isUser: false, text: accumulated, timestamp: Date())
                    }
                }

                // 串流結束：如果完全沒有任何文字，就不留下空泡泡
                if botIndex == nil {
                    // 什麼都沒產生，不動 messages
                } else if let idx = botIndex {
                    self.memory.append(self.messages[idx])
                }

            } catch is CancellationError {
                // 被取消：若尚未產生任何文字，就不要放 AI 氣泡；已產生則保留現有內容
            } catch {
                // 錯誤：只有在「已經有文字」前提下才覆蓋提示；否則不新增空泡
                if let idx = botIndex {
                    self.messages[idx] = ChatMessage(isUser: false,
                                                     text: "（連線失敗，請稍後再試）",
                                                     timestamp: Date())
                } else {
                    // 未產生任何字，什麼都不加
                }
            }

            self.isTyping = false
            self.currentTask = nil
        }
    }

    func applyPersona() async {
        let p = Persona(id: "p1", name: personaName, basePrompt: personaPrompt)
        do { try await ChatAPI.updatePersona(p) } catch { }
    }

    func rememberLike(_ key: String, _ value: String) async {
        do { try await ChatAPI.updateMemory(userId: userId, keyValues: [key: value]) } catch { }
    }
}
