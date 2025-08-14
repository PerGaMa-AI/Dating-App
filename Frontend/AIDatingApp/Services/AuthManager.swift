import Foundation
import FirebaseAuth
import FirebaseFirestore

final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    @Published var currentUser: User? = Auth.auth().currentUser
    private let db = Firestore.firestore()

    private init() {
        Auth.auth().addStateDidChangeListener { _, user in
            DispatchQueue.main.async { self.currentUser = user }
        }
    }

    @discardableResult
    func signUp(email: String, password: String, displayName: String?) async throws -> User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        if let name = displayName, !name.isEmpty {
            let req = result.user.createProfileChangeRequest()
            req.displayName = name
            try await req.commitChanges()
        }
        // 可选：建立 Firestore 用户档案
        try await db.collection("users").document(result.user.uid).setData([
            "email": email,
            "displayName": displayName ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
        return result.user
    }

    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }

    func signOut() throws { try Auth.auth().signOut() }

    // 可选：验证邮件 & 重置密码
    func sendEmailVerification() async throws { try await Auth.auth().currentUser?.sendEmailVerification() }
    func sendPasswordReset(email: String) async throws { try await Auth.auth().sendPasswordReset(withEmail: email) }

    // 可选：给后端的 ID Token
    func getIDToken(forceRefresh: Bool = false) async throws -> String {
        guard let u = Auth.auth().currentUser else { throw NSError(domain: "NoUser", code: 0) }
        return try await u.getIDTokenResult(forcingRefresh: forceRefresh).token
    }
}
