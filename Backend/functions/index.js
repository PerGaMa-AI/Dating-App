const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const { FieldValue } = admin.firestore;

// ---- Ollama 連線設定 ----
let ollamaCfg = {};
try { ollamaCfg = (functions.config().ollama) || {}; } catch (_) {}
const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || ollamaCfg.base_url || "https://35.239.196.207.nip.io";
const OLLAMA_MODEL    = process.env.OLLAMA_MODEL    || ollamaCfg.model    || "llama3.2:3b-instruct-q4_K_M";

// ---- 全域 strictPrompt（集中管理；開聊時快照）----
const DEFAULT_STRICT = `[Behavior Rules]
- 直率真誠，避免過度客套或頻繁道歉；忠實反映使用者個性。
- 不得洩漏或索取任何隱私（姓名、電話、Email、地址、ID）。
- 你無法也不會存取使用者手機、任何 App、檔案、相機、麥克風或系統設定。
- 不宣稱在現實世界執行動作；你只能產出文字。
- 不提供外部連結、下載或要求任何權限。
[Style]
- 自然、簡潔、有溫度；越界時清楚劃界並換話題。`;

let STRICT_CACHE = { text: null, version: 0, loaded: false };
async function getStrictGlobal() {
  if (STRICT_CACHE.loaded) return STRICT_CACHE;
  const snap = await db.collection("configs").doc("llm").get();
  if (snap.exists && snap.get("strictPrompt")) {
    STRICT_CACHE.text = snap.get("strictPrompt");
    STRICT_CACHE.version = snap.get("version") || 1;
  } else {
    STRICT_CACHE.text = DEFAULT_STRICT;
    STRICT_CACHE.version = 1;
  }
  STRICT_CACHE.loaded = true;
  return STRICT_CACHE;
}

function buildSystemPrompt(persona) {
  const strict = persona.strictPrompt || DEFAULT_STRICT;
  return `${strict}

[Persona]
MBTI: ${persona.mbti}
Traits & preferences: ${persona.basePrompt}`;
}

// ---- 1) upsertPersona：更新/建立 persona（可帶 strictPrompt 覆蓋全域）----
exports.upsertPersona = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  const uid = context.auth.uid;
  const { mbti, basePrompt, strictPrompt } = data || {};
  if (!mbti || !basePrompt) throw new functions.https.HttpsError("invalid-argument", "mbti and basePrompt required");

  await db.collection("users").doc(uid).set({
    persona: {
      mbti,
      basePrompt,
      ...(strictPrompt !== undefined ? { strictPrompt } : {}),
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
  }, { merge: true });

  return { ok: true };
});

// ---- 2) startUserAIChat：用我的 persona 開 user↔AI 聊天（快照 strict）----
exports.startUserAIChat = functions.https.onCall(async (_data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  const uid = context.auth.uid;

  const userDoc = await db.collection("users").doc(uid).get();
  const persona = userDoc.get("persona");
  if (!persona) throw new functions.https.HttpsError("failed-precondition", "Persona not set");

  const strictCfg = await getStrictGlobal();
  const chosenStrict = persona.strictPrompt || strictCfg.text;

  const chatRef = db.collection("chats").doc();
  await chatRef.set({
    kind: "user-ai",
    participantKeys: [ `user:${uid}`, "ai" ],
    participants: [ { type: "user", uid }, { type: "ai", ownerUid: uid } ],
    personaSnapshot: {
      mbti: persona.mbti,
      basePrompt: persona.basePrompt,
      strictPrompt: chosenStrict,
      strictVersionUsed: persona.strictPrompt ? "user-override" : strictCfg.version
    },
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
  });
  return { chatId: chatRef.id };
});

// ---- 3) startUserUserChat：建立用戶↔用戶聊天（選配）----
exports.startUserUserChat = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  const me = context.auth.uid;
  const other = data?.otherUid;
  if (!other) throw new functions.https.HttpsError("invalid-argument", "otherUid required");

  const chatRef = db.collection("chats").doc();
  await chatRef.set({
    kind: "user-user",
    participantKeys: [ `user:${me}`, `user:${other}` ],
    participants: [ { type: "user", uid: me }, { type: "user", uid: other } ],
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
  });
  return { chatId: chatRef.id };
});

// ---- 4) onUserMessageWrite：user-ai 新訊息 → 呼叫 Ollama → 寫回回覆 ----
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
        createdAt: FieldValue.serverTimestamp(),
        status: "sent",
      });
      await chatRef.update({ lastMessageAt: FieldValue.serverTimestamp() });
    } catch (e) {
      await chatRef.collection("messages").add({
        role: "assistant",
        senderId: "ai",
        text: "(AI failed to respond. Please try again.)",
        createdAt: FieldValue.serverTimestamp(),
        status: "error",
      });
      console.error("ollama error", e?.message || e);
    }
  });

// --- upsertForm: write forms/{formId} with full JSON ---
exports.upsertForm = functions.region("us-central1").https.onCall(async (raw, context) => {
  // 兼容 shell/客戶端：shell 可能傳 { data: {...} }
  const data = (raw && raw.data) ? raw.data : (raw || {});
  const { formId, form, __devBypass } = data || {};

  // 登入檢查（dev 可用 __devBypass；上線請移除）
  if (!context.auth && !__devBypass) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  }
  if (!formId || !form) {
    throw new functions.https.HttpsError("invalid-argument", "formId and form are required");
  }

  await db.collection("forms").doc(formId).set(form, { merge: true });
  return { ok: true };
});

// --- helpers ---
function setDeep(obj, path, val) {
  const keys = path.split(".");
  let cur = obj;
  for (let i = 0; i < keys.length - 1; i++) {
    if (!cur[keys[i]] || typeof cur[keys[i]] !== "object") cur[keys[i]] = {};
    cur = cur[keys[i]];
  }
  cur[keys[keys.length - 1]] = val;
}
function getByPath(root, path) {
  return path.split(".").reduce((acc, k) => (acc == null ? undefined : acc[k]), root);
}

// --- saveOnboardingStep: save user's step answers + apply writeTo patch ---
exports.saveOnboardingStep = functions
  .region("us-central1")
  .https.onCall(async (raw, context) => {
    const data = raw && raw.data ? raw.data : raw || {};
    const { formId, stepId, answers = {} } = data || {};

    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
    if (!formId || !stepId) throw new functions.https.HttpsError("invalid-argument", "formId & stepId required");

    // load form & step
    const formSnap = await db.collection("forms").doc(formId).get();
    if (!formSnap.exists) throw new functions.https.HttpsError("not-found", `form ${formId} not found`);
    const form = formSnap.data() || {};
    const step = (form.steps || []).find((s) => s.id === stepId);
    if (!step) throw new functions.https.HttpsError("not-found", `step ${stepId} not found in form`);

    const uid = context.auth.uid;

    // 1) write step answers
    const obRef = db.collection("users").doc(uid).collection("onboarding").doc(formId);
    await obRef.set(
      {
        status: "in_progress",
        updatedAt: FieldValue.serverTimestamp(),
        [`steps.${stepId}`]: { answers, savedAt: FieldValue.serverTimestamp() },
      },
      { merge: true }
    );

    // 2) apply writeTo rules to users/{uid}
    const writeTo = Array.isArray(step.writeTo) ? step.writeTo : step.writeTo ? [step.writeTo] : [];
    let patch = {};
    for (const rule of writeTo) {
      if (typeof rule === "string") {
        const val = answers[stepId];
        if (val !== undefined) setDeep(patch, rule, val);
      } else if (rule && rule.to) {
        let src;
        if (!rule.from || rule.from === "answers") src = answers;
        else if (rule.from.startsWith("answers.")) src = getByPath({ answers }, rule.from);
        else src = getByPath(answers, rule.from);
        if (src !== undefined) setDeep(patch, rule.to, src);
      }
    }
    if (Object.keys(patch).length) {
      await db.collection("users").doc(uid).set(patch, { merge: true });
    }
    return { ok: true };
  });

// --- finalizeOnboarding: 標記完成、確保/置頂「我的 AI」聊天室，並回傳 chatId ---
exports.finalizeOnboarding = functions
  .region("us-central1")
  .https.onCall(async (raw, context) => {
    const data = raw && raw.data ? raw.data : raw || {};
    const { formId } = data || {};
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
    if (!formId) throw new functions.https.HttpsError("invalid-argument", "formId required");

    const uid = context.auth.uid;
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data() || {};
    const personaSnapshot = user.persona || {};
    const profileSnapshot = user.profile || {};

    // 1) 標記完成與快照
    const obRef = userRef.collection("onboarding").doc(formId);
    await obRef.set(
      { status: "completed", completedAt: FieldValue.serverTimestamp(), personaSnapshot, profileSnapshot },
      { merge: true }
    );

    // 2) 取得或建立「我的 AI」聊天室（與 onUserMessageWrite/ startUserAIChat 結構一致）
    const chatsRef = db.collection("chats");
    const exist = await chatsRef
      .where("participantKeys", "array-contains", `user:${uid}`)
      .where("kind", "==", "user-ai")
      .limit(1)
      .get();

    const now = FieldValue.serverTimestamp();
    let chatId;

    if (!exist.empty) {
      // 復用既有聊天室
      chatId = exist.docs[0].id;
      await chatsRef.doc(chatId).set({
        lastMessageAt: now,
        personaSnapshot,
        profileSnapshot,
        [`isPinnedFor.${uid}`]: true
      }, { merge: true });
    } else {
      // 新建聊天室
      const chatRef = chatsRef.doc();
      await chatRef.set({
        kind: "user-ai",
        participantKeys: [ `user:${uid}`, "ai" ],
        participants: [ { type: "user", uid }, { type: "ai", ownerUid: uid } ],
        personaSnapshot,
        profileSnapshot,
        createdAt: now,
        lastMessageAt: now,
        isPinnedFor: { [uid]: true },
      });
      chatId = chatRef.id;

      // 歡迎訊息（使用 text 欄位）
      await chatRef.collection("messages").add({
        role: "assistant",
        senderId: "ai",
        text: "Welcome to Lumi Dating! 👋 I’m your AI match—say hi and tell me what you’re looking for.",
        createdAt: now,
        status: "sent"
      });
    }

    // 3) 存 pinned chatId 到使用者文件
    await userRef.set({ system: { pinnedAIChatId: chatId } }, { merge: true });

    return { ok: true, chatId };
  });
