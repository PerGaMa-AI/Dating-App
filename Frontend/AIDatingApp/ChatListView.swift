//
//  ChatListView.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/13/25.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatThread: Identifiable {
    let id: String
    let title: String
    let lastMessageAt: Date?
    let isPinned: Bool
}

final class ChatListVM: ObservableObject {
    @Published var threads: [ChatThread] = []
    private var listener: ListenerRegistration?

    func start() async {
        if Auth.auth().currentUser == nil { _ = try? await Auth.auth().signInAnonymously() }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        listener?.remove()
        listener = db.collection("chats")
            .whereField("participantKeys", arrayContains: "user:\(uid)")
            .order(by: "lastMessageAt", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let docs = snap?.documents {
                    let rows: [ChatThread] = docs.map { d in
                        let data = d.data()
                        let isPinned = (data["isPinnedFor"] as? [String: Bool])?[uid] == true
                        let ts = data["lastMessageAt"] as? Timestamp
                        let kind = data["kind"] as? String ?? "user-ai"
                        let title = (kind == "user-ai") ? "我的 AI 人格" : "聊天"
                        return ChatThread(id: d.documentID,
                                          title: title,
                                          lastMessageAt: ts?.dateValue(),
                                          isPinned: isPinned)
                    }
                    self.threads = rows.sorted {
                        if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                        return ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast)
                    }
                }
            }
    }

    deinit { listener?.remove() }
}

struct ChatListView: View {
    @StateObject private var vm = ChatListVM()

    var body: some View {
        NavigationStack {
            List(vm.threads) { t in
                NavigationLink(destination: ChatView(chatId: t.id)) {
                    HStack {
                        Text(t.title)
                        if t.isPinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                        Spacer()
                        if let dt = t.lastMessageAt {
                            Text(dt.formatted(date: .omitted, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .task { await vm.start() }
        }
    }
}

