import SwiftUI

struct SignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorText: String?
    let onGoSignUp: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Sign In").font(.largeTitle).bold()
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let err = errorText { Text(err).foregroundColor(.red).font(.footnote) }

            Button("Sign In") {
                Task {
                    do { _ = try await AuthManager.shared.signIn(email: email, password: password) }
                    catch { errorText = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Create an account") { onGoSignUp() }
                .font(.footnote)
        }
        .padding()
    }
}
