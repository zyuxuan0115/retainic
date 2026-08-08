//
//  repository.js
//  Retainic Web
//
//  Firestore + Storage read/write helpers. A faithful port of
//  VocabRepository.swift using the Firebase Web SDK. Documents are shaped
//  identically to the iOS app's, so both clients share the same data:
//
//    users/{uid}                                 -> profile
//    users/{uid}/lists/{listId}                  -> list
//    users/{uid}/lists/{listId}/words/{wordId}   -> word
//    users/{uid}/glossaries/{glossaryId}                   -> glossary
//    users/{uid}/glossaries/{glossaryId}/entries/{entryId} -> glossary entry
//    users/{uid}/dailyStats/{yyyy-MM-dd}         -> daily tally
//

import { db, storage } from "./firebase.js";
import {
  collection, collectionGroup, doc, getDoc, getDocs, setDoc, addDoc, updateDoc, deleteDoc,
  query, where, orderBy, limit, increment, Timestamp, deleteField, writeBatch,
} from "https://www.gstatic.com/firebasejs/11.0.2/firebase-firestore.js";
import {
  ref as storageRef, uploadBytes, getDownloadURL, deleteObject,
} from "https://www.gstatic.com/firebasejs/11.0.2/firebase-storage.js";
import { refreshMemorization } from "./models.js";

// MARK: - Date / document normalization

/** Recursively turn Firestore Timestamps into JS Dates so the SRS code (which
 *  does Date math) works on fetched documents. */
function fromFirestore(value) {
  if (value == null) return value;
  if (value instanceof Timestamp) return value.toDate();
  if (Array.isArray(value)) return value.map(fromFirestore);
  if (typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = fromFirestore(v);
    return out;
  }
  return value;
}

/** Strip the local-only `id` field, the retired `box` field, and any
 *  `undefined`s before writing. Dropping `box` here means it's removed from a
 *  word document the next time that word is saved. Glossary entries, which
 *  never had a `box`, go through the same cleanup. */
function toFirestore(word) {
  const out = {};
  for (const [k, v] of Object.entries(word)) {
    if (k === "id" || k === "box" || v === undefined) continue;
    out[k] = v;
  }
  return out;
}

// MARK: - Paths

const userDoc = (uid) => doc(db, "users", uid);
const listsRef = (uid) => collection(db, "users", uid, "lists");
const wordsRef = (uid, listId) => collection(db, "users", uid, "lists", listId, "words");
const dailyStatsRef = (uid) => collection(db, "users", uid, "dailyStats");
const glossariesRef = (uid) => collection(db, "users", uid, "glossaries");
const entriesRef = (uid, glossaryId) => collection(db, "users", uid, "glossaries", glossaryId, "entries");

// MARK: - Daily stats

/** "yyyy-MM-dd" key in the local calendar, used for daily-stat documents. */
export function dayKey(date) {
  const d = new Date(date);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

const DAILY_FIELD = { spelling: "word", translation: "translation", pronunciation: "pronunciation" };

/** The daily fields glossary practice writes on top of the shared ones, so the
 *  glossary charts have a history of their own without disturbing the combined
 *  totals every other chart is drawn from. */
const GLOSSARY_DAILY_FIELD = { term: "glossaryTerm", definition: "glossaryDefinition" };

/** Increments today's remembered count for the given aspect. Glossary practice
 *  passes `glossaryAspect` as well, tallying the same recall under both the
 *  shared field and its own in one write. */
export async function recordRemembered(uid, aspect, { glossaryAspect = null, date = new Date() } = {}) {
  const update = { date: dayKey(date) };
  const field = DAILY_FIELD[aspect];
  if (field) update[field] = increment(1);
  const glossaryField = GLOSSARY_DAILY_FIELD[glossaryAspect];
  if (glossaryField) update[glossaryField] = increment(1);
  if (Object.keys(update).length === 1) return;
  await setDoc(doc(dailyStatsRef(uid), update.date), update, { merge: true });
}

/** Most recent `days` daily-stat documents (chronological order). */
export async function fetchDailyStats(uid, days) {
  const snap = await getDocs(query(dailyStatsRef(uid), orderBy("date", "desc"), limit(days)));
  const stats = snap.docs.map((d) => ({ id: d.id, ...fromFirestore(d.data()) }));
  return stats.sort((a, b) => (a.date < b.date ? -1 : 1));
}

// MARK: - Profile

export async function fetchProfile(uid) {
  const snap = await getDoc(userDoc(uid));
  return snap.exists() ? fromFirestore(snap.data()) : null;
}

export async function createProfile(uid, profile) {
  await setDoc(userDoc(uid), profile);
}

// MARK: - Invitation codes

/** Whether the given invitation code exists. Codes are stored as document IDs
 *  under `invitationCodes`; the security rules allow a single-doc `get` (so a
 *  code you already know can be verified, even before signing in) but forbid
 *  listing, so the set can't be enumerated. */
export async function isValidInvitationCode(code) {
  const trimmed = (code || "").trim();
  if (!trimmed) return false;
  try {
    const snap = await getDoc(doc(db, "invitationCodes", trimmed));
    return snap.exists();
  } catch {
    return false;
  }
}

// MARK: - Lists

/** A stable per-list identifier: a 64-character SHA-256 hex string (letters and
 *  numbers only), independent of the Firestore document ID. */
async function generateListPublicId() {
  const seed = crypto.getRandomValues(new Uint8Array(32));
  const digest = await crypto.subtle.digest("SHA-256", seed);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Ensures each list has a `publicId`, generating and persisting one for any
 *  that predate the field. Best-effort: a failed write won't break the read. */
async function backfillPublicIds(uid, lists) {
  for (const list of lists) {
    if (list.publicId) continue;
    const publicId = await generateListPublicId();
    list.publicId = publicId;
    try { await updateDoc(doc(listsRef(uid), list.id), { publicId }); } catch {}
  }
}

/** Active (non-trashed) lists, newest first. Trashed lists carry a `deletedAt`
 *  timestamp and are filtered out here — see `fetchTrashedLists`. */
export async function fetchLists(uid) {
  const snap = await getDocs(query(listsRef(uid), orderBy("createdAt", "desc")));
  const lists = snap.docs
    .map((d) => ({ id: d.id, ...fromFirestore(d.data()) }))
    .filter((list) => !list.deletedAt);
  await backfillPublicIds(uid, lists);
  return lists;
}

/** Lists currently in the trash, most recently deleted first. */
export async function fetchTrashedLists(uid) {
  const snap = await getDocs(listsRef(uid));
  const lists = snap.docs
    .map((d) => ({ id: d.id, ...fromFirestore(d.data()) }))
    .filter((list) => list.deletedAt)
    .sort((a, b) => (a.deletedAt < b.deletedAt ? 1 : -1));
  await backfillPublicIds(uid, lists);
  return lists;
}

export async function createList(uid, name, learningLanguage, originalLanguage) {
  const publicId = await generateListPublicId();
  const list = { name, createdAt: new Date(), wordCount: 0, learningLanguage, originalLanguage, publicId };
  const ref = await addDoc(listsRef(uid), list);
  return ref.id;
}

export async function renameList(uid, listId, name) {
  await updateDoc(doc(listsRef(uid), listId), { name });
}

/** Turns the per-list text-to-speech fallback on or off. */
export async function setListTTS(uid, listId, enabled) {
  await updateDoc(doc(listsRef(uid), listId), { ttsEnabled: enabled });
}

/** Stores this list's custom review-algorithm Python, or clears it (back to the
 *  built-in default) when `code` is null. */
export async function setListAlgorithm(uid, listId, code) {
  await updateDoc(doc(listsRef(uid), listId), { algorithmCode: code == null ? deleteField() : code });
}

/** Finds any user's list by its shared `publicId` and returns its metadata and
 *  words (raw), or null if no list has that ID. Uses a collection-group query,
 *  so it can read another account's list (the security rules allow cross-user
 *  reads of lists/words; writes stay owner-only). */
export async function fetchSharedList(publicId) {
  const trimmed = (publicId || "").trim();
  if (!trimmed) return null;
  const snap = await getDocs(query(collectionGroup(db, "lists"), where("publicId", "==", trimmed), limit(1)));
  if (snap.empty) return null;
  const d = snap.docs[0];
  const list = { id: d.id, ...fromFirestore(d.data()) };
  // Never hand another account's custom review algorithm to this client. It is
  // executable Python (run via Pyodide, which can reach the page's JavaScript),
  // so importing and running someone else's would be remote code execution in
  // the viewer's browser. Only the owner ever keeps/runs their own algorithm.
  delete list.algorithmCode;
  const wordsSnap = await getDocs(collection(d.ref, "words"));
  const words = wordsSnap.docs.map((w) => ({ id: w.id, ...fromFirestore(w.data()) }));
  return { list, words };
}

/** Soft-delete: move a list to the trash by stamping `deletedAt`. Its words and
 *  audio are left untouched so the list can be restored intact. */
export async function trashList(uid, listId) {
  await updateDoc(doc(listsRef(uid), listId), { deletedAt: new Date() });
}

/** Restore a trashed list by clearing its `deletedAt` stamp. */
export async function restoreList(uid, listId) {
  await updateDoc(doc(listsRef(uid), listId), { deletedAt: deleteField() });
}

/** Permanently delete a list, its words, and any pronunciation audio. */
export async function purgeList(uid, listId) {
  const words = await getDocs(wordsRef(uid, listId));
  // Only a word with a recording has anything in Storage, and those deletes
  // don't have to wait on each other — emptying the Trash of a list that never
  // had audio now costs no Storage requests at all.
  await Promise.all(words.docs
    .map((d) => d.data().audioPath)
    .filter(Boolean)
    .map((path) => deleteAudio(path)));
  await deleteDocuments(words.docs.map((d) => d.ref), doc(listsRef(uid), listId));
}

// MARK: - Words

export async function fetchWords(uid, listId) {
  const snap = await getDocs(query(wordsRef(uid, listId), orderBy("createdAt", "desc")));
  return snap.docs.map((d) => ({ id: d.id, ...fromFirestore(d.data()) }));
}

export async function addWord(uid, listId, word, audioBlob = null) {
  const ref = doc(wordsRef(uid, listId));
  const w = { ...word };
  if (audioBlob) {
    const path = audioStoragePath(uid, listId, ref.id);
    await uploadAudio(audioBlob, path);
    w.audioPath = path;
  }
  await setDoc(ref, toFirestore(w));
  await updateDoc(doc(listsRef(uid), listId), { wordCount: increment(1) });
  return ref.id;
}

/** The most documents one batch writes. A batch takes 500 operations, and each
 *  one here spends its last on the parent's count of them. */
const BATCH_LIMIT = 499;

/** Deletes many documents in batches — emptying the Trash of a long list is one
 *  round trip per 499 documents instead of one per document. `parent` (the list
 *  or glossary itself) goes last, in the final batch, so a failure part-way
 *  through leaves it in the Trash to be purged again rather than orphaning the
 *  documents still under it. */
async function deleteDocuments(refs, parent) {
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const chunk = refs.slice(i, i + BATCH_LIMIT);
    const batch = writeBatch(db);
    for (const ref of chunk) batch.delete(ref);
    if (i + BATCH_LIMIT >= refs.length) batch.delete(parent);
    await batch.commit();
  }
  // A list or glossary with nothing under it still has itself to delete.
  if (!refs.length) await deleteDoc(parent);
}

/** Writes many words at once, for the import flows. Storing them in batches
 *  costs one round trip per 499 words instead of two per word, and each batch
 *  either lands whole or not at all. Imported words never carry audio, so
 *  there's nothing to upload alongside them. */
export async function addWords(uid, listId, words) {
  for (let i = 0; i < words.length; i += BATCH_LIMIT) {
    const chunk = words.slice(i, i + BATCH_LIMIT);
    const batch = writeBatch(db);
    for (const word of chunk) batch.set(doc(wordsRef(uid, listId)), toFirestore(word));
    batch.update(doc(listsRef(uid), listId), { wordCount: increment(chunk.length) });
    await batch.commit();
  }
}

/** Updates a word. Pass `audioBlob` to (re)upload a recording, or
 *  `removeAudio: true` to delete it. With neither, audioPath is preserved.
 *  `ttsEnabled` is the list's text-to-speech setting, so mastery is recomputed
 *  against the right pronunciation requirement when the recording changes. */
export async function updateWord(uid, listId, word, { audioBlob = null, removeAudio = false, ttsEnabled = false } = {}) {
  if (!word.id) return;
  const w = { ...word };
  const path = audioStoragePath(uid, listId, word.id);
  if (audioBlob) {
    await uploadAudio(audioBlob, path);
    w.audioPath = path;
    refreshMemorization(w, ttsEnabled);
  } else if (removeAudio) {
    await deleteAudio(path);
    w.audioPath = null;
    refreshMemorization(w, ttsEnabled);
  }
  await setDoc(doc(wordsRef(uid, listId), word.id), toFirestore(w));
}

export async function deleteWord(uid, listId, wordId) {
  await deleteAudio(audioStoragePath(uid, listId, wordId));
  await deleteDoc(doc(wordsRef(uid, listId), wordId));
  await updateDoc(doc(listsRef(uid), listId), { wordCount: increment(-1) });
}

/** Moves a word to another list, preserving fields, progress, and audio. */
export async function moveWord(uid, fromListId, toListId, word) {
  if (!word.id || fromListId === toListId) return;
  const newWord = { ...word, id: undefined, audioPath: null };
  delete newWord.id;

  let blob = null;
  if (word.audioPath) {
    try { blob = await downloadAudioBlob(word.audioPath); } catch {}
  }
  await addWord(uid, toListId, newWord, blob);
  await deleteWord(uid, fromListId, word.id);
}

// MARK: - Glossaries
//
// Glossaries live in their own collection and share nothing with lists: a
// glossary has one language, and its entries are a term and a definition. Like
// lists, deleting one is a soft delete (`deletedAt`) so it can be restored from
// the Trash.

/** Active (non-trashed) glossaries, newest first. */
export async function fetchGlossaries(uid) {
  const snap = await getDocs(query(glossariesRef(uid), orderBy("createdAt", "desc")));
  return snap.docs
    .map((d) => ({ id: d.id, ...fromFirestore(d.data()) }))
    .filter((glossary) => !glossary.deletedAt);
}

/** Glossaries currently in the trash, most recently deleted first. */
export async function fetchTrashedGlossaries(uid) {
  const snap = await getDocs(glossariesRef(uid));
  return snap.docs
    .map((d) => ({ id: d.id, ...fromFirestore(d.data()) }))
    .filter((glossary) => glossary.deletedAt)
    .sort((a, b) => (a.deletedAt < b.deletedAt ? 1 : -1));
}

export async function createGlossary(uid, name, language) {
  const glossary = { name, language, createdAt: new Date(), entryCount: 0 };
  const ref = await addDoc(glossariesRef(uid), glossary);
  return ref.id;
}

export async function renameGlossary(uid, glossaryId, name) {
  await updateDoc(doc(glossariesRef(uid), glossaryId), { name });
}

/** Stores this glossary's custom review-algorithm Python, or clears it (back to
 *  the built-in default) when `code` is null. */
export async function setGlossaryAlgorithm(uid, glossaryId, code) {
  await updateDoc(doc(glossariesRef(uid), glossaryId), { algorithmCode: code == null ? deleteField() : code });
}

export async function trashGlossary(uid, glossaryId) {
  await updateDoc(doc(glossariesRef(uid), glossaryId), { deletedAt: new Date() });
}

export async function restoreGlossary(uid, glossaryId) {
  await updateDoc(doc(glossariesRef(uid), glossaryId), { deletedAt: deleteField() });
}

/** Permanently delete a glossary and its entries. */
export async function purgeGlossary(uid, glossaryId) {
  const entries = await getDocs(entriesRef(uid, glossaryId));
  await deleteDocuments(entries.docs.map((d) => d.ref), doc(glossariesRef(uid), glossaryId));
}

// MARK: - Glossary entries

export async function fetchEntries(uid, glossaryId) {
  const snap = await getDocs(query(entriesRef(uid, glossaryId), orderBy("createdAt", "desc")));
  return snap.docs.map((d) => ({ id: d.id, ...fromFirestore(d.data()) }));
}

export async function addEntry(uid, glossaryId, entry) {
  const ref = await addDoc(entriesRef(uid, glossaryId), toFirestore(entry));
  await updateDoc(doc(glossariesRef(uid), glossaryId), { entryCount: increment(1) });
  return ref.id;
}

/** Writes many entries at once, for the CSV import — one round trip per 499
 *  terms instead of two per term, each batch landing whole or not at all. */
export async function addEntries(uid, glossaryId, entries) {
  for (let i = 0; i < entries.length; i += BATCH_LIMIT) {
    const chunk = entries.slice(i, i + BATCH_LIMIT);
    const batch = writeBatch(db);
    for (const entry of chunk) batch.set(doc(entriesRef(uid, glossaryId)), toFirestore(entry));
    batch.update(doc(glossariesRef(uid), glossaryId), { entryCount: increment(chunk.length) });
    await batch.commit();
  }
}

export async function updateEntry(uid, glossaryId, entry) {
  if (!entry.id) return;
  await setDoc(doc(entriesRef(uid, glossaryId), entry.id), toFirestore(entry));
}

export async function deleteEntry(uid, glossaryId, entryId) {
  await deleteDoc(doc(entriesRef(uid, glossaryId), entryId));
  await updateDoc(doc(glossariesRef(uid), glossaryId), { entryCount: increment(-1) });
}

// MARK: - Pronunciation audio (Firebase Storage)

export function audioStoragePath(uid, listId, wordId) {
  return `users/${uid}/lists/${listId}/words/${wordId}/pronunciation.m4a`;
}

async function uploadAudio(blob, path) {
  await uploadBytes(storageRef(storage, path), blob, {
    contentType: blob.type || "audio/mp4",
    // Let browsers/CDN cache the clip so repeat plays don't re-download. A
    // re-recording overwrites the path and gets a fresh download token, so a
    // long max-age is safe (each version has its own tokenized URL).
    cacheControl: "public, max-age=604800",
  });
}

export async function audioURL(path) {
  return getDownloadURL(storageRef(storage, path));
}

async function downloadAudioBlob(path) {
  const url = await getDownloadURL(storageRef(storage, path));
  const res = await fetch(url);
  return res.blob();
}

async function deleteAudio(path) {
  try { await deleteObject(storageRef(storage, path)); } catch {}
}
