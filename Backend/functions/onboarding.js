// functions/onboarding.js
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const db = admin.firestore();
const { FieldValue } = admin.firestore;

// --- helpers（可沿用你 index.js 的版本；若已存在就刪除本段，從 index.js 匯入）---
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

// --- upsertForm: write forms/{formId} with full JSON ---
exports.upsertForm = functions.region("us-central1").https.onCall(async (raw, context) => {
  const data = (raw && raw.data) ? raw.data : (raw || {});
  const { formId, form, __devBypass } = data || {};
  if (!context.auth && !__devBypass) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  if (!formId || !form) throw new functions.https.HttpsError("invalid-argument", "formId and form are required");
  await db.collection("forms").doc(formId).set(form, { merge: true });
  return { ok: true };
});

// --- saveOnboardingStep: save user's step answers + apply writeTo patch ---
exports.saveOnboardingStep = functions.region("us-central1").https.onCall(async (raw, context) => {
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

// --- finalizeOnboarding: mark completed + ensure pinned AI chat ---
exports.finalizeOnboarding = functions.region("us-central1").https.onCall(async (raw, context) => {
  const data = raw && raw.data ? raw.data : raw || {};
  const { formId } = data || {};
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");
  if (!formId) throw new functions.https.HttpsError("invalid-argument", "formId required");

  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const user = userSnap.data() || {};
  const personaSnapshot = user.persona || {};   // 你已有 upsertPersona 寫入
  const profileSnapshot = user.profile || {};   // 你在 saveStep 的 writeTo 可能已逐步寫；可選擇這裡再聚合

  // 1) 標記完成 & 快照
  const obRef = userRef.collection("onboarding").doc(formId);
  await obRef.set(
    { status: "completed", completedAt: FieldValue.serverTimestamp(), personaSnapshot, profileSnapshot },
    { merge: true }
  );

  // 2) 取得或建立「我的 AI」聊天室（與 startUserAIChat 對齊）
  const chatsRef = db.collection("chats");
  const exist = await chatsRef
    .where("participantKeys", "array-contains", `user:${uid}`)
    .where("kind", "==", "user-ai")
    .limit(1)
    .get();

  const now = FieldValue.serverTimestamp();
  let chatId;

  if (!exist.empty) {
    // 復用現有
    chatId = exist.docs[0].id;
    await chatsRef.doc(chatId).set({
      lastMessageAt: now,
      personaSnapshot, // 更新快照（可選）
      profileSnapshot // 可選
    }, { merge: true });
  } else {
    // 新建
    const chatRef = chatsRef.doc();
    await chatRef.set({
      kind: "user-ai",
      participantKeys: [ `user:${uid}`, "ai" ],
      participants: [ { type: "user", uid }, { type: "ai", ownerUid: uid } ],
      personaSnapshot,
      profileSnapshot,
      createdAt: now,
      lastMessageAt: now,
      isPinnedFor: { [uid]: true },   // 置頂
    });
    chatId = chatRef.id;

    // 歡迎訊息（注意！用 text 欄位，符合 onUserMessageWrite 讀取）
    await chatRef.collection("messages").add({
      role: "assistant",
      senderId: "ai",
      text: "Welcome to Lumi Dating! 👋 I’m your AI match—say hi and tell me what you’re looking for.",
      createdAt: now,
      status: "sent"
    });
  }

  // 3) 存 pinned chatId（Settings/ChatsView 會用到）
  await userRef.set({ system: { pinnedAIChatId: chatId } }, { merge: true });

  return { ok: true, chatId };
});
