//
//  AIDatingAppApp.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
// AIDatingAppApp.swift
// AIDatingAppApp.swift
import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@main
struct AIDatingAppApp: App {
    init() {
        FirebaseApp.configure()

        // 🔎 印出目前連到的 Firebase 專案/金鑰/Bundle（保留你的除錯輸出）
        if let app = FirebaseApp.app() {
            let opt = app.options
            print("""
            🔎 Firebase config:
              projectID   = \(opt.projectID ?? "nil")
              googleAppID = \(opt.googleAppID)
              apiKey      = \(opt.apiKey)
              gcmSenderID = \(opt.gcmSenderID ?? "nil")
              bundleID    = \(Bundle.main.bundleIdentifier ?? "nil")
            """)
        } else {
            print("❌ FirebaseApp not configured")
        }

        // （可保留）先行匿名登入；RootGate 內也會保險簽一次，不會衝突
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { result, error in
                if let error = error {
                    print("❌ Anonymous sign-in failed:", error)
                } else {
                    print("✅ Signed in as:", result?.user.uid ?? "nil")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            // ✅ 入口改為 Gate：會自動判斷 Onboarding 或主分頁
            RootGateView()
        }
    }
}
