//
//  MainTabsView.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/13/25.
//
import SwiftUI

struct MainTabsView: View {
    let pinnedAIChatId: String? // 目前未使用；未來可用來預設打開置頂聊天室

    var body: some View {
        TabView {
            MatchView()
                .tabItem { Label("Match", systemImage: "heart.fill") }

            TBDView()
                .tabItem { Label("Discover", systemImage: "safari") }

            // 聊天清單頁（由 ChatListView 負責）
            ChatListView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

// 先放占位頁
struct MatchView: View { var body: some View { Text("Match").padding() } }
struct TBDView: View { var body: some View { Text("Coming soon").padding() } }
struct SettingsView: View { var body: some View { Text("Settings").padding() } }
