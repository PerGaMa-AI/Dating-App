//
//  AppConfig.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/11/25.
//
import Foundation

enum AppConfig {
    // 雲端入口（你現在的 Caddy 反代）
    static let ollamaBaseURL  = URL(string: "https://35.239.196.207.nip.io")!

    // 如果你還有自家的後端（.backendProxy 用得到），保留/自行調整
    static let backendBaseURL = URL(string: "https://your-backend.example.com/")!
}
