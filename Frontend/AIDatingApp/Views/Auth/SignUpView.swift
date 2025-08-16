//
//  SignUpView.swift
//  AIDatingApp
//
//  Created by Xiaomeng Jiang on 8/15/25.
//


import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var focused: Field?

    enum Field { case name, email, password, confirm }

    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Display Name (optional)", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .name)

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .email)

            SecureField("Password (min 6)", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .password)

            SecureField("Confirm Password", text: $confirm)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .confirm)

            if let err = errorText {
                Text(err).foregroundColor(.red).font(.footnote)
            }

            HStack {
                Button {
                    Task { await signUp() }
                } label: {
                    HStack {
                        if isBusy { ProgressView().padding(.trailing, 6) }
                        Text("Create Account")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || !isFormValid)

                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 6)

            Text("By signing up, you agree to our Terms and Privacy Policy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { focused = .name }
    }

    private var isFormValid: Bool {
        let mailOK = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let pwOK = password.count >= 6 && password == confirm
        return mailOK && pwOK
    }

    private func signUp() async {
        guard isFormValid else {
            await MainActor.run { errorText = "Please check email and password (≥ 6, match confirm)." }
            return
        }
        await MainActor.run { isBusy = true; errorText = nil }

        do {
            // 1) Create
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            // 2) Profile display name (optional)
            if !displayName.isEmpty {
                let req = result.user.createProfileChangeRequest()
                req.displayName = displayName
                try await req.commitChanges()
            }

            // 3) (Optional) Create Firestore user profile
            let db = Firestore.firestore()
            try await db.collection("users").document(result.user.uid).setData([
                "email": email,
                "profile": [
                    "displayName": displayName
                ],
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)

            // 4) (Optional) Send verification email (可根据需要开启)
            // try? await result.user.sendEmailVerification()

            await MainActor.run {
                isBusy = false
                onDone()
            }
        } catch {
            await MainActor.run {
                isBusy = false
                errorText = error.localizedDescription
            }
        }
    }
}
