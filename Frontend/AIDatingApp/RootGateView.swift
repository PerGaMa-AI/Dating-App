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
    
    //监听 Auth 状态
    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        //登录/退出都会回调这里
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            guard let self = self else { return }
            Task { await self.boot() }
        }
    }

    deinit {
        obListener?.remove()
        userListener?.remove()
        //移除监听
        if let h = authHandle {
            Auth.auth().removeStateDidChangeListener(h)
        }
    }

    /// 使用 async，並在 View 以 `.task { await boot() }` 呼叫
    func boot() async {
        // 1) 確保有身份
//        if Auth.auth().currentUser == nil {
//            _ = try? await Auth.auth().signInAnonymously()
//        }
//        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // 未登录就直接放行到 Auth 界面
     
        let user = Auth.auth().currentUser
        guard let uid = user?.uid, user?.isAnonymous == false else {
            await MainActor.run { isLoading = false }
            return
        }

        
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
//            if gate.isLoading {
//                ProgressView("Booting…")

//            } else if Auth.auth().currentUser == nil {
//                AuthSwitcherView()
//
            //未登录时显示登录/注册界面
            let user = Auth.auth().currentUser
            if user == nil || user?.isAnonymous == true  {
                AuthSwitcherView(onSignedIn: {
                Task { await gate.boot() }
            })
            //已登录但仍在加载监听
            } else if gate.isLoading {
                ProgressView("Booting…")

            } else if gate.shouldShowOnboarding {
                // 把 gate 注入 Onboarding，完成時也能手動切換（雙保險）
                OnboardingFlowView().environmentObject(gate)
                
            } else {
                MainTabsView(pinnedAIChatId: gate.pinnedAIChatId)
            }

        }
        // 以 async 方式啟動 gate
        .task { await gate.boot() }
    }
}
