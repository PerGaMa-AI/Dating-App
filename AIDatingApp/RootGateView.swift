//
//  RootGateView.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/13/25.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

final class AppGateVM: ObservableObject {
    @Published var isLoading = true
    @Published var shouldShowOnboarding = true
    @Published var pinnedAIChatId: String?

    private let formId = "onboarding_v1"
    private var obListener: ListenerRegistration?
    private var userListener: ListenerRegistration?

    deinit {
        obListener?.remove()
        userListener?.remove()
    }

    /// 使用 async，並在 View 以 `.task { await boot() }` 呼叫
    func boot() async {
        // 1) 確保有身份
        if Auth.auth().currentUser == nil {
            _ = try? await Auth.auth().signInAnonymously()
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        await MainActor.run { self.isLoading = true }

        // 2) 清掉舊監聽，重新掛上
        obListener?.remove()
        userListener?.remove()

        // 監聽 onboarding 狀態（完成後立刻切頁）
        obListener = db.collection("users").document(uid)
            .collection("onboarding").document(formId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let status = snap?.data()?["status"] as? String
                Task { @MainActor in
                    self.shouldShowOnboarding = (status != "completed")
                    self.isLoading = false
                }
            }

        // 監聽 pinnedAIChatId（finalize 後會寫入）
        userListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let pinned = (snap?.data()?["system"] as? [String: Any])?["pinnedAIChatId"] as? String
                Task { @MainActor in
                    self.pinnedAIChatId = pinned
                }
            }
    }
}

struct RootGateView: View {
    @StateObject private var gate = AppGateVM()

    var body: some View {
        Group {
            if gate.isLoading {
                ProgressView("Booting…")
            } else if gate.shouldShowOnboarding {
                // 把 gate 注入 Onboarding，完成時也能手動切換（雙保險）
                OnboardingFlowView()
                    .environmentObject(gate)
            } else {
                MainTabsView(pinnedAIChatId: gate.pinnedAIChatId)
            }
        }
        // 以 async 方式啟動 gate
        .task { await gate.boot() }
    }
}
