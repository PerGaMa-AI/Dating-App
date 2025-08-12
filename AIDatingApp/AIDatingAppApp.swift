//
//  AIDatingAppApp.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
import SwiftUI

@main
struct AIDatingAppApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {        // 或 NavigationView
                ChatView()           // ← 換成你的聊天畫面
            }
        }
    }
}
