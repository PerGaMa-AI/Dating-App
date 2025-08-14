//
//  OnboardingService.swift
//  AIDatingApp
// OnboardingService.swift
import Foundation
import FirebaseAuth
import FirebaseFunctions

/// 單一職責：處理登入與 Cloud Functions 呼叫
final class OnboardingService {
    static let shared = OnboardingService()
    private init() {}

    private let functions = Functions.functions(region: "us-central1")

    /// 確保有身分（匿名登入或刷新 token）
    func ensureSignedIn() async throws {
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        } else {
            _ = try await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: false)
        }
    }

    /// 儲存某一步的答案
    func saveStep(formId: String, stepId: String, answers: [String: Any]) async throws {
        try await ensureSignedIn()
        let payload: [String: Any] = [
            "formId": formId,
            "stepId": stepId,
            "answers": answers
        ]
        _ = try await functions.httpsCallable("saveOnboardingStep").call(payload)
    }

    /// 完成 Onboarding，回傳 chatId（可能為 nil）
    @discardableResult
    func finalize(formId: String) async throws -> String? {
        try await ensureSignedIn()
        let res = try await functions
            .httpsCallable("finalizeOnboarding")
            .call(["formId": formId])
        return (res.data as? [String: Any])?["chatId"] as? String
    }
}

