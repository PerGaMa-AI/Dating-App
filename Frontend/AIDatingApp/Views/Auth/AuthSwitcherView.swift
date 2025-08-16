//
//  AuthSwitcherView.swift
//  AIDatingApp
//
//  Created by Xiaomeng Jiang on 8/15/25.
//
import SwiftUI


struct AuthSwitcherView: View {
    /// 登录/注册成功后的回调；在 RootGateView 里会传入： { Task { await gate.boot() } }
    var onSignedIn: () -> Void = {}

    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isSignUp {
                    SignUpView(
                        onDone: {
                            isSignUp = false
                            onSignedIn()
                        },
                        onCancel: { isSignUp = false }
                    )
                } else {
                    SignInView(
                        onGoSignUp: { isSignUp = true },
                        onSignedIn: onSignedIn
                    )
                }
            }
            .padding()
            .navigationTitle(isSignUp ? "Create Account" : "Sign In")
        }
    }
}
