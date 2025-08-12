//
//  ChatView.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/10/25.
//
import SwiftUI
import UIKit

// 小頭像
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

// 單則訊息行（含左右對齊與頭像）
struct MessageRow: View {
    let m: ChatMessage
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !m.isUser { AvatarView(isUser: false) }   // 左邊：AI 頭像
            Text(m.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(m.isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 320, alignment: m.isUser ? .trailing : .leading) // 泡泡寬上限
            if m.isUser { AvatarView(isUser: true) }     // 右邊：使用者頭像
        }
        // 讓整行靠左或靠右
        .frame(maxWidth: .infinity, alignment: m.isUser ? .trailing : .leading)
        // 留出另一側的邊距，避免貼邊
        .padding(m.isUser ? .leading : .trailing, 48)
    }
}

struct ChatView: View {
    @StateObject var vm = ChatViewModel()

    var body: some View {
        VStack {
            // 人格設定
            Form {
                Section("人格設定") {
                    TextField("名字", text: $vm.personaName)
                    TextEditor(text: $vm.personaPrompt).frame(height: 80)
                    Button("套用人格") { Task { await vm.applyPersona() } }
                }
            }.frame(height: 200)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { m in
                            MessageRow(m: m).id(m.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            // 🔹 對方正在輸入提示
            if vm.isTyping {
                Text("對方正在輸入…")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }

            // 輸入欄
            HStack {
                TextField("跟人格說點什麼…", text: $vm.input)
                    .textFieldStyle(.roundedBorder)
                Button("送出") { Task { await vm.send() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("AI 戀愛人格")
    }
}

