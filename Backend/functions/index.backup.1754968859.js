const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();
const db = admin.firestore();



let cfg = {};
try { cfg = functions.config().ollama || {}; } catch (_) {}
const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || cfg.base_url || "https://35.239.196.207.nip.io";
const OLLAMA_MODEL    = process.env.OLLAMA_MODEL    || cfg.model    || "llama3.2:3b-instruct-q4_K_M";

function buildSystemPrompt(persona) {
  return `You are a flirty but respectful dating persona.
MBTI: ${persona.mbti}.
Traits & preferences: ${persona.basePrompt}.
Be concise, empathetic, and never share private data. Avoid explicit content.`;
}

// upsertPersona：寫入/更新使用者的 persona
exports.upsertPersona = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  const uid = context.auth.uid;
  const { mbti, basePrompt } = data || {};
  if (!mbti || !basePrompt) throw new functions.https.HttpsError("invalid-argument", "mbti and basePrompt required");

  await db.collection("users").doc(uid).set({
    persona: {
      mbti,
      basePrompt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  }, { merge: true });

  return { ok: true };
});

// startUserAIChat：建立 user↔AI 聊天並快照 persona
exports.startUserAIChat = functions.https.onCall(async (_data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  const uid = context.auth.uid;
  const userDoc = await db.collection("users").doc(uid).get();
  const persona = userDoc.get("persona");
  if (!persona) throw new functions.https.HttpsError("failed-precondition", "Persona not set");

  const chatRef = db.collection("chats").doc();
  await chatRef.set({
    participants: [uid, "ai"],
    kind: "user-ai",
    personaSnapshot: { mbti: persona.mbti, basePrompt: persona.basePrompt },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { chatId: chatRef.id };
});

// 當 user 在 user-ai 聊天新增訊息 → 呼叫 Ollama → 寫回 AI 回覆
exports.onUserMessageWrite = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const msg = snap.data();
    if (!msg || msg.role !== "user") return;

    const chatId = context.params.chatId;
    const chatRef = db.collection("chats").doc(chatId);
    const chatSnap = await chatRef.get();
    if (!chatSnap.exists) return;
    const chat = chatSnap.data();
    if (!chat || chat.kind !== "user-ai") return;

    const persona = chat.personaSnapshot || { mbti: "ENFP", basePrompt: "" };

    // 取最近 20 則歷史
    const histSnap = await chatRef.collection("messages")
      .orderBy("createdAt", "asc").limitToLast(20).get();
    const history = histSnap.docs.map(d => d.data());

    const systemPrompt = buildSystemPrompt(persona);
    const ollamaMessages = [
      { role: "system", content: systemPrompt },
      ...history.map(m => ({ role: m.role, content: m.text })),
    ];

    try {
      const res = await axios.post(`${OLLAMA_BASE_URL}/api/chat`, {
        model: OLLAMA_MODEL,
        messages: ollamaMessages,
        stream: false,
      }, { timeout: 60000 });

      const aiText =
        (res.data && res.data.message && res.data.message.content) ||
        (res.data && res.data.choices && res.data.choices[0] && res.data.choices[0].message && res.data.choices[0].message.content) ||
        "(no reply)";

      await chatRef.collection("messages").add({
        role: "assistant",
        senderId: "ai",
        text: aiText,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "sent",
      });
      await chatRef.update({ lastMessageAt: admin.firestore.FieldValue.serverTimestamp() });
    } catch (e) {
      await chatRef.collection("messages").add({
        role: "assistant",
        senderId: "ai",
        text: "(AI failed to respond. Please try again.)",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "error",
      });
      console.error("ollama error", e && e.message ? e.message : e);
    }
  });
