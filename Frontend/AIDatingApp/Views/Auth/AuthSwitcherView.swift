import SwiftUI

struct AuthSwitcherView: View {
    @State private var isSignUp = false

    var body: some View {
        VStack(spacing: 16) {
            if isSignUp {
                SignUpView(onDone: { isSignUp = false })
            } else {
                SignInView(onGoSignUp: { isSignUp = true })
            }
        }
        .padding()
    }
}
