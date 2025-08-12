//
//  ChatAPI.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//
import Foundation

// 這個檔提供兩種用法：
// 1) ChatAPIStream.streamMessage(...)  → 推薦：即時串流，每個增量直接丟回 UI
// 2) ChatAPI.sendMessage(...)          → 相容：內部用串流累積成整段後回傳

struct ChatAPIStream {
    /// 串流聊天：每個增量（token 片段）都會 yield 出來
    static func streamMessage(
        userId: String,
        content: String,
        systemPrompt: String? = "你是溫柔的戀愛人格。用精簡、口語化回覆。"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // 直連雲端 Ollama
                    let url = LLMConfig.baseURL.appendingPathComponent("api/chat")
                    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
                    req.httpMethod = "POST"
                    req.addValue("application/json", forHTTPHeaderField: "Content-Type")

                    // ⚙️ 推薦的快取參數（CPU 機最佳化）
                    let body: [String: Any] = [
                        "model": LLMConfig.model, // 建議在 LLMConfig 裡設為 "llama3.2:3b-instruct-q4_K_M"
                        "messages": [
                            ["role": "system", "content": systemPrompt ?? ""],
                            ["role": "user",   "content": content]
                        ],
                        "stream": true,
                        "keep_alive": "30m",
                        "options": [
                            "num_predict": 120,  // 限長：縮短尾段等待
                            "num_thread": 4,     // e2-standard-4 → 4 threads
                            "num_ctx": 1536,     // 降低前置計算
                            "num_keep": 128,
                            "num_batch": 64,     // 提升 token/s（記憶體足夠時）
                            "stop": ["\n\n","User:","使用者："]
                        ]
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }

                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        guard let data = line.data(using: .utf8),
                              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let err = obj["error"] as? String {
                            throw NSError(domain: "Ollama", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
                        }
                        if let msg = obj["message"] as? [String: Any],
                           let delta = msg["content"] as? String,
                           !delta.isEmpty {
                            continuation.yield(delta) // 逐段吐字
                        }
                        if (obj["done"] as? Bool) == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

struct ChatAPI {

    /// 相容版：回傳整段文字（內部其實用串流收齊）
    static func sendMessage(userId: String, content: String) async throws -> String {
        switch LLMProvider.current {

        case .backendProxy:
            // 維持你原本的後端代理路徑
            let url = AppConfig.backendBaseURL.appendingPathComponent("chat")
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "userId": userId,
                "message": content
            ])
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["reply"] as? String ?? "(no reply)"

        case .directOllama:
            // 新：內部用串流，但對外回傳整段字串（保持你現有 call site 不用改）
            var full = ""
            do {
                for try await delta in ChatAPIStream.streamMessage(
                    userId: userId,
                    content: content,
                    systemPrompt: "你是真實反映這位用戶的戀愛人格、用簡單口語化回覆、避免長篇的回覆。"
                ) {
                    full += delta
                }
                return full.isEmpty ? "(no reply)" : full
            } catch {
                // 🛟 Fallback：非串流一次性
                let url = LLMConfig.baseURL.appendingPathComponent("api/chat")
                var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
                req.httpMethod = "POST"
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")

                // 注意：fallback 也用同一個模型，避免不一致
                let body: [String: Any] = [
                    "model": LLMConfig.model,
                    "messages": [
                        ["role": "system", "content": "你是真實反映這位用戶的戀愛人格、用簡單口語化回覆、避免長篇的回覆。"],
                        ["role": "user",   "content": content]
                    ],
                    "stream": false,
                    "keep_alive": "30m",
                    "options": [
                        "num_predict": 120,
                        "num_thread": 4,
                        "num_ctx": 1536,
                        "num_keep": 128,
                        "num_batch": 64
                    ]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

                // /api/chat（stream=false）返回：{ "message": { "role":"assistant","content":"..." }, ... }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let err = json?["error"] as? String {
                    throw NSError(domain: "OllamaError", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
                }
                if let msg = json?["message"] as? [String: Any],
                   let content = msg["content"] as? String {
                    return content
                }
                return "(no reply)"
            }
        }
    }

    // 更新人格（寫到你的後端 DB；MVP 可先存記憶體）
    static func updatePersona(_ p: Persona) async throws {
        let url = AppConfig.backendBaseURL.appendingPathComponent("persona")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "PUT"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(p)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    // （可選）更新記憶：如關鍵值、摘要等
    static func updateMemory(userId: String, keyValues: [String:String]) async throws {
        let url = AppConfig.backendBaseURL.appendingPathComponent("memory")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "userId": userId,
            "kv": keyValues
        ])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }
}
