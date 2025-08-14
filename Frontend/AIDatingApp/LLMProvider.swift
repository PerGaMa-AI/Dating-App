//
//  LLMProvider.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//
import Foundation

struct GenerateReq: Codable { let model: String; let prompt: String; let stream: Bool }
struct GenerateRes: Codable { let response: String }

final class LLMProvider {
    static let shared = LLMProvider()

    func generate(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = LLMConfig.baseURL.appendingPathComponent("/api/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = GenerateReq(model: LLMConfig.model, prompt: prompt, stream: false) // 先關閉串流，簡單測
        req.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            guard err == nil, let data = data,
                  let res = try? JSONDecoder().decode(GenerateRes.self, from: data)
            else { return completion(.failure(err ?? URLError(.badServerResponse))) }
            completion(.success(res.response))
        }.resume()
    }
}

// 在 LLMProvider.swift 底部加：路由枚舉 + 當前路由
enum LLMRoute {
    case backendProxy
    case directOllama
}

extension LLMProvider {
    /// App 目前要走哪條路徑（直連雲端 Ollama，或你自家後端代理）
    static var current: LLMRoute = .directOllama
}
