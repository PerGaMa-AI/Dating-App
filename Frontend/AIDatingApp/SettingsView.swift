//
//  SettingsView.swift
//  AIDatingApp
//
//  Created by Xiaomeng Jiang on 8/15/25.
//


import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @State private var showConfirm = false
    @State private var isSigningOut = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    if isSigningOut {
                        ProgressView()
                    } else {
                        Text("Sign Out")
                    }
                }
                .disabled(isSigningOut)
                .confirmationDialog("Sign out of your account?",
                                   isPresented: $showConfirm,
                                   titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        Task { await signOut() }
                    }
                    Button("Cancel", role: .cancel) {}
                }

                if let err = errorText {
                    Text(err).foregroundColor(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func signOut() async {
        await MainActor.run {
            isSigningOut = true
            errorText = nil
        }
        do {
            try Auth.auth().signOut()
            // 完成：RootGateView 会监听到登录状态变化并切回登录页
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
        await MainActor.run { isSigningOut = false }
    }
}
