//
//  ChatView.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//
import SwiftUI
import UIKit

// MARK: - 小頭像
struct AvatarView: View {
    let isUser: Bool
    var body: some View {
        ZStack {
            Circle().fill(isUser ? Color.blue.opacity(0.2) : Color.pink.opacity(0.2))
            Image(systemName: isUser ? "person.circle.fill" : "pawprint.circle.fill")
                .resizable().scaledToFit()
                .padding(4)
                .foregroundStyle(isUser ? .blue : .pink)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - 單則訊息行（含左右對齊與頭像）
struct MessageRow: View {
    let m: ChatMessage
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !m.isUser { AvatarView(isUser: false) }   // 左：AI
            Text(m.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(m.isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 320, alignment: m.isUser ? .trailing : .leading)
            if m.isUser { AvatarView(isUser: true) }     // 右：User
        }
        .frame(maxWidth: .infinity, alignment: m.isUser ? .trailing : .leading)
        .padding(m.isUser ? .leading : .trailing, 48)
    }
}

// MARK: - 聊天室畫面（支援可選 chatId）
struct ChatView: View {
    @StateObject private var vm: ChatViewModel

    /// 可外部指定 chatId；若不指定，VM 會自動找 pinned AI chat，沒有就建立
    init(chatId: String? = nil) {
        _vm = StateObject(wrappedValue: ChatViewModel(chatId: chatId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // （可選）人格設定
            Form {
                Section("人格設定") {
                    TextField("名字", text: $vm.personaName)
                    TextEditor(text: $vm.personaPrompt).frame(height: 80)
                    Button("套用人格") { Task { await vm.applyPersona() } }
                }
            }
            .frame(height: 200)

            // 訊息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { m in
                            MessageRow(m: m).id(m.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = vm.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // 對方正在輸入
            if vm.isTyping {
                Text("對方正在輸入…")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            // 輸入欄
            HStack(spacing: 10) {
                TextField("跟人格說點什麼…", text: $vm.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { Task { await vm.send() } }

                Button {
                    Task { await vm.send() }
                } label: {
                    Text("送出")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .navigationTitle("AI 戀愛人格")
        .navigationBarTitleDisplayMode(.inline)
    }
}
