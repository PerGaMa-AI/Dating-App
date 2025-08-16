//
//  OnboardingFlowView.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/13/25.
//
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ViewModel（用外部 OnboardingService.shared）
final class OnboardingVM: ObservableObject {
  @Published var form: FormDef?
  @Published var currentId: String?
  @Published var isBusy = false
  @Published var errorText: String?

  let formId = "onboarding_v1"
  private let service = OnboardingService.shared

  // 讀取 Firestore 上的表單
  func boot() async {
    // 建議：先確保有身份，避免 rules 限制讀不到 forms/*
//    if Auth.auth().currentUser == nil {
//      _ = try? await Auth.auth().signInAnonymously()
//    }
      guard Auth.auth().currentUser != nil else {
          await MainActor.run { self.errorText = "Please sign in first" }
          return
      }

    do {
      let db = Firestore.firestore()
      let snap = try await db.collection("forms").document(formId).getDocument()
      guard let data = snap.data() else { throw NSError(domain: "no_form", code: 1) }
      let raw = try JSONSerialization.data(withJSONObject: data, options: [])
      let f = try JSONDecoder().decode(FormDef.self, from: raw)

      await MainActor.run {
        self.form = f
        self.currentId = f.steps.first?.id
      }
    } catch {
      await MainActor.run { self.errorText = "Load form failed: \(error.localizedDescription)" }
    }
  }

  func currentStep() -> StepDef? {
    guard let form, let id = currentId else { return nil }
    return form.steps.first(where: { $0.id == id })
  }

  private func goNext(from step: StepDef) {
    guard let form else { return }
    if let nxt = step.next {
      currentId = nxt
    } else if let idx = form.steps.firstIndex(where: { $0.id == step.id }),
              idx + 1 < form.steps.count {
      currentId = form.steps[idx + 1].id
    } else {
      currentId = nil
    }
  }

  /// 儲存一步答案（service 內含 ensureSignedIn）
  func submit(step: StepDef, answers: [String:Any]) async {
    guard !isBusy else { return }
    await MainActor.run { isBusy = true; errorText = nil }
    do {
      try await service.saveStep(formId: formId, stepId: step.id, answers: answers)
      await MainActor.run {
        isBusy = false
        goNext(from: step)
      }
    } catch {
      await MainActor.run {
        isBusy = false
        errorText = "Save failed: \(error.localizedDescription)"
      }
    }
  }

  /// 完成 Onboarding（回傳 chatId）
  func finish() async -> String? {
    guard !isBusy else { return nil }
    await MainActor.run { isBusy = true; errorText = nil }
    do {
      let chatId = try await service.finalize(formId: formId) // String?
      await MainActor.run { isBusy = false }
      return chatId
    } catch {
      await MainActor.run {
        isBusy = false
        errorText = "Finalize failed: \(error.localizedDescription)"
      }
      return nil
    }
  }
}

// MARK: - UI（整合 Gate：完成後切到 Tabs）
struct OnboardingFlowView: View {
  @EnvironmentObject private var gate: AppGateVM   // ✅ 從 RootGate 注入
  @StateObject private var vm = OnboardingVM()

  var body: some View {
    NavigationStack {
      Group {
        if let step = vm.currentStep() {
          StepRenderer(step: step) { ans in
            Task { await vm.submit(step: step, answers: ans) }
          } onFinish: {
            Task {
              let chatId = await vm.finish()
              print("🎉 chatId:", chatId ?? "nil")
              await MainActor.run {
                if let cid = chatId, !cid.isEmpty {
                  gate.pinnedAIChatId = cid
                }
                gate.shouldShowOnboarding = false
              }
            }
          }
        } else if vm.form != nil {
          VStack(spacing: 12) {
            Text("All done!").font(.title2).bold()
            Text("You can now go to chat.")
            Button("Open Chat") {
              // 若走到這裡（少見），也切 Gate
              gate.shouldShowOnboarding = false
            }
            .buttonStyle(.borderedProminent)
          }
        } else {
          ProgressView("Loading form…")
        }
      }
      .padding()
      .navigationTitle("Onboarding")
      .task { await vm.boot() }
      .alert("Error",
             isPresented: Binding(get: { vm.errorText != nil },
                                  set: { _ in vm.errorText = nil })) {
        Button("OK", role: .cancel) { vm.errorText = nil }
      } message: {
        Text(vm.errorText ?? "")
      }
    }
  }
}

// MARK: - StepRenderer（保持你的 UI，微調 disabled 邏輯）
struct StepRenderer: View {
  let step: StepDef
  let onNext: ([String:Any]) -> Void
  let onFinish: () -> Void

  @State private var singleValue: String = ""
  @State private var multiValues: Set<String> = []
  @State private var textValue: String = ""
  @State private var numberValue: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !step.displayTitle.isEmpty { Text(step.displayTitle).font(.title2).bold() }
      if let desc = step.description { Text(desc).foregroundStyle(.secondary) }

      switch step.type {
      case .intro:
        Button("Get started") { onNext([:]) }

      case .choice, .singleSelect:
        Picker("", selection: $singleValue) {
          ForEach(step.options ?? []) { opt in Text(opt.label).tag(opt.value) }
        }
        .pickerStyle(.inline)
        Button("Next") { onNext([step.id: singleValue]) }
          .disabled((step.required ?? false) && singleValue.isEmpty)

      case .multiSelect:
        List(step.options ?? []) { opt in
          MultipleSelectionRow(
            title: opt.label,
            isSelected: multiValues.contains(opt.value)
          ) {
            if multiValues.contains(opt.value) { multiValues.remove(opt.value) }
            else { multiValues.insert(opt.value) }
          }
        }
        .listStyle(.inset)
        Button("Next") {
          // 與你的 writeTo schema 對齊（需求不同可改 key）
          onNext(["interests": Array(multiValues)])
        }
        .disabled((step.required ?? false) && multiValues.isEmpty)

      case .text:
        TextField(step.placeholder ?? "", text: $textValue)
          .textFieldStyle(.roundedBorder)
        Button("Next") { onNext([step.id: textValue]) }
          .disabled((step.required ?? false) && textValue.isEmpty)

      case .textarea:
        TextEditor(text: $textValue).frame(minHeight: 120)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        Button("Next") { onNext([step.id: textValue]) }
          .disabled((step.required ?? false) && textValue.isEmpty)

      case .number:
        TextField(step.placeholder ?? "", text: $numberValue)
          .keyboardType(.numberPad)
          .textFieldStyle(.roundedBorder)
        Button("Next") {
          let n = Int(numberValue) ?? 0
          onNext([step.id: n])
        }
        .disabled((Int(numberValue) ?? -1) < (step.validation?["min"] ?? 0))

      case .upload:
        Text("Photo upload will be added later (PHPicker + Firebase Storage).")
          .foregroundStyle(.secondary)
        Button("Skip for now") { onNext([:]) }

      case .finish:
        Button("Finish") { onFinish() }
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

private struct MultipleSelectionRow: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack { Text(title); Spacer(); if isSelected { Image(systemName: "checkmark") } }
    }
  }
}
