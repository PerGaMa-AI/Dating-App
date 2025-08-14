import SwiftUI

struct SignUpView: View {
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorText: String?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Sign Up").font(.largeTitle).bold()
            TextField("Display Name", text: $displayName).textFieldStyle(.roundedBorder)
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)
            SecureField("Password (min 6)", text: $password).textFieldStyle(.roundedBorder)

            if let err = errorText { Text(err).foregroundColor(.red).font(.footnote) }

            Button("Create Account") {
                Task {
                    do {
                        _ = try await AuthManager.shared.signUp(
                            email: email, password: password, displayName: displayName
                        )
                        try? await AuthManager.shared.sendEmailVerification()
                        onDone()
                    } catch { errorText = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
