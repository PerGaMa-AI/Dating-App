//
//  SignInView.swift
//  AIDatingApp
//
//  Created by Xiaomeng Jiang on 8/15/25.
//


import SwiftUI
import FirebaseAuth

struct SignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var focused: Field?

    enum Field { case email, password }

    let onGoSignUp: () -> Void
    let onSignedIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .email)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .password)
            }

            if let err = errorText {
                Text(err).foregroundColor(.red).font(.footnote)
            }

            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    if isBusy { ProgressView().padding(.trailing, 6) }
                    Text("Sign In")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || !isFormValid)

            HStack {
                Button("Forgot password?") {
                    Task { await resetPassword() }
                }
                .font(.footnote)

                Spacer()

                Button("Create an account") {
                    onGoSignUp()
                }
                .font(.footnote)
            }
            .padding(.top, 4)
        }
        .onAppear { focused = .email }
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    private func signIn() async {
        guard isFormValid else { return }
        await MainActor.run { isBusy = true; errorText = nil }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            await MainActor.run {
                isBusy = false
                onSignedIn()
            }
        } catch {
            await MainActor.run {
                isBusy = false
                errorText = error.localizedDescription
            }
        }
    }

    private func resetPassword() async {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mail.isEmpty else {
            await MainActor.run { errorText = "Please enter your email above first." }
            return
        }
        await MainActor.run { isBusy = true; errorText = nil }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: mail)
            await MainActor.run {
                isBusy = false
                errorText = "Password reset email sent."
            }
        } catch {
            await MainActor.run {
                isBusy = false
                errorText = error.localizedDescription
            }
        }
    }
}
