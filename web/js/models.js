//
//  models.js
//  Retainic Web
//
//  Port of PartOfSpeech.swift and the Leitner / per-aspect spaced-repetition
//  helpers from FirestoreModels.swift. Words are plain objects shaped exactly
//  like the Firestore documents the iOS app reads and writes.
//

// MARK: - Parts of speech

export const PARTS_OF_SPEECH = [
  "noun", "verb", "adjective", "adverb",
  "pronoun", "preposition", "conjunction", "interjection",
];

const POS_LABELS = {
  en: { noun: "Noun", verb: "Verb", adjective: "Adjective", adverb: "Adverb", pronoun: "Pronoun", preposition: "Preposition", conjunction: "Conjunction", interjection: "Interjection" },
  es: { noun: "Sustantivo", verb: "Verbo", adjective: "Adjetivo", adverb: "Adverbio", pronoun: "Pronombre", preposition: "Preposición", conjunction: "Conjunción", interjection: "Interjección" },
  zh: { noun: "名词", verb: "动词", adjective: "形容词", adverb: "副词", pronoun: "代词", preposition: "介词", conjunction: "连词", interjection: "感叹词" },
  ja: { noun: "名詞", verb: "動詞", adjective: "形容詞", adverb: "副詞", pronoun: "代名詞", preposition: "前置詞", conjunction: "接続詞", interjection: "感動詞" },
  ko: { noun: "명사", verb: "동사", adjective: "형용사", adverb: "부사", pronoun: "대명사", preposition: "전치사", conjunction: "접속사", interjection: "감탄사" },
};

export function posLabel(raw, code = "en") {
  // Normalize case so legacy/mixed-case stored values (e.g. "Noun") still match
  // the lowercase keys and localize, rather than falling back to English.
  const key = String(raw).toLowerCase();
  const table = POS_LABELS[code] || POS_LABELS.en;
  return table[key] || (key.charAt(0).toUpperCase() + key.slice(1));
}

/** The inverse of posLabel(): the part-of-speech key a label names, in any
 *  supported language, or null when it names none. Used to read parts of speech
 *  back out of an imported CSV. */
export function posKey(label) {
  const value = String(label).trim().toLowerCase();
  if (!value) return null;
  if (PARTS_OF_SPEECH.includes(value)) return value;
  for (const table of Object.values(POS_LABELS)) {
    for (const [key, localized] of Object.entries(table)) {
      if (localized.toLowerCase() === value) return key;
    }
  }
  return null;
}

// MARK: - Spaced-repetition schedule

function startOfDay(date) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

function daysBetween(last, now) {
  const ms = startOfDay(now) - startOfDay(last);
  return Math.round(ms / 86400000);
}

export function isSameDay(a, b) {
  if (!a || !b) return false;
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}

export function isToday(date) {
  return date ? isSameDay(date, new Date()) : false;
}

// MARK: - Pluggable review algorithm
//
// A word's schedule and mastery are computed by a "review" function. Given the
// word's current state it returns, for each of the three methods, the number of
// days until that method is due again (-1 = finished), plus `masteredTotal` —
// the total correct-count at which the word counts as fully memorized. A list
// can override this with its own Python (compiled via Pyodide in algorithm.js);
// with no override the built-in `defaultReview` below runs.

/** The state a review function sees for a word. `ttsEnabled` is the list's
 *  text-to-speech setting: with it on the word is spoken by a synthesized voice,
 *  so pronunciation is practised — and therefore required for mastery — even
 *  without its own recording. */
function reviewState(word, ttsEnabled = false) {
  return {
    times_word: word.timesWordCorrect ?? 0,
    times_translation: word.timesTranslationCorrect ?? 0,
    times_pronunciation: word.timesPronounciationCorrect ?? 0,
    has_audio: word.audioPath != null || ttsEnabled === true,
  };
}

/** The built-in schedule, matching the app's original gaps and mastery rule:
 *  8× Word + 10× Translation (+ 7× Audio once the word has a recording). */
export function defaultReview(s) {
  const WORD = [0, 1, 1, 2, 3, 4, 6, 9];
  const TRANSLATION = [0, 1, 1, 1, 2, 2, 3, 4, 5, 10];
  const PRONUNCIATION = [0, 1, 2, 3, 4, 6, 8];
  const gap = (table, n) => (n < table.length ? table[n] : -1);
  return {
    word: gap(WORD, s.times_word),
    translation: gap(TRANSLATION, s.times_translation),
    pronunciation: gap(PRONUNCIATION, s.times_pronunciation),
    masteredTotal: WORD.length + TRANSLATION.length + (s.has_audio ? PRONUNCIATION.length : 0),
  };
}

let activeReview = defaultReview;

/** Installs a compiled review override, or resets to the default when null. */
export function setActiveAlgorithm(fn) {
  activeReview = fn || defaultReview;
}

/** Whether a method is due: not finished (interval >= 0), and either never
 *  practised yet or its interval of days has elapsed since it was last correct. */
function methodDue(interval, last, now) {
  if (interval == null || interval < 0) return false;
  if (!last) return true;
  return daysBetween(last, now) >= interval;
}

// MARK: - Word helpers (operate on plain word objects)

/** Selected parts of speech, reading the array field then the legacy single. */
export function partOfSpeechValues(word) {
  // Normalize to lowercase keys so display, filtering, and the edit-sheet
  // checkbox matching all work regardless of how the value was stored.
  if (Array.isArray(word.partsOfSpeech) && word.partsOfSpeech.length) {
    return word.partsOfSpeech.map((p) => String(p).toLowerCase()).filter((p) => p && p !== "unspecified");
  }
  if (word.partOfSpeech) {
    const single = String(word.partOfSpeech).toLowerCase();
    if (single !== "unspecified") return [single];
  }
  return [];
}

/** Phonetic reading to display (hiragana for Japanese, pinyin for Chinese). */
export function reading(word) {
  for (const v of [word.hiragana, word.pinyin]) {
    if (v && v.length) return v;
  }
  return null;
}

/** The reading shown on the term side, chosen by the list's learning language. */
export function readingFor(word, learningLanguage) {
  let value;
  if (learningLanguage === "zh") value = word.pinyin;
  else if (learningLanguage === "ja") value = word.hiragana;
  else value = reading(word);
  return value && value.length ? value : null;
}

export function isRemembered(word) {
  return word.remember_final === true;
}

export function isTranslationDue(word, now = new Date(), ttsEnabled = false) {
  return methodDue(activeReview(reviewState(word, ttsEnabled)).translation, word.lastTranslationRemembered, now);
}

export function isWordDue(word, now = new Date(), ttsEnabled = false) {
  return methodDue(activeReview(reviewState(word, ttsEnabled)).word, word.lastWordRemembered, now);
}

export function isPronunciationDue(word, now = new Date(), ttsEnabled = false) {
  return methodDue(activeReview(reviewState(word, ttsEnabled)).pronunciation, word.lastPronounciationRemembered, now);
}

/** Re-evaluates whether the word is finally remembered. Per the active
 *  algorithm, a word is fully memorized once the sum of its three correct-counts
 *  (Word + Translation + Audio) reaches the algorithm's `masteredTotal`.
 *  Pronunciation counts toward that total when the word has a recording or the
 *  list has text-to-speech on (see `reviewState`). */
function updateRememberFinal(word, ttsEnabled = false) {
  const s = reviewState(word, ttsEnabled);
  const total = s.times_word + s.times_translation + s.times_pronunciation;
  word.remember_final = total >= activeReview(s).masteredTotal;
}

/** Re-evaluates mastery after the word's pronunciation requirement may have
 *  changed — a recording was added or removed, or the list's text-to-speech
 *  setting was toggled. Turning either on introduces the 7× pronunciation
 *  requirement, so a word mastered without it is demoted until it is recalled by
 *  pronunciation enough times; turning both off drops the requirement again
 *  while keeping the pronunciation count. Call whenever `audioPath` or the
 *  list's `ttsEnabled` changes. */
export function refreshMemorization(word, ttsEnabled = false) {
  updateRememberFinal(word, ttsEnabled);
}

function record(word, aspect, correct, now) {
  if (!aspect) return;
  const stats = word.memoryStats || {};
  const entry = stats[aspect] || { seen: 0, timesRemembered: 0, lastRemembered: null };
  entry.seen += 1;
  if (correct) {
    entry.timesRemembered += 1;
    entry.lastRemembered = now;
  }
  stats[aspect] = entry;
  word.memoryStats = stats;
}

/** Records a correct recall for the given aspect (mutates the word). Pass the
 *  list's `ttsEnabled` so mastery is re-evaluated against the same pronunciation
 *  requirement the learner is practising under. */
export function markCorrect(word, aspect, ttsEnabled = false) {
  const now = new Date();
  word.timesSeen = (word.timesSeen ?? 0) + 1;
  switch (aspect) {
    case "spelling":
      word.timesWordCorrect = (word.timesWordCorrect ?? 0) + 1;
      word.lastWordRemembered = now;
      break;
    case "pronunciation":
      word.timesPronounciationCorrect = (word.timesPronounciationCorrect ?? 0) + 1;
      word.lastPronounciationRemembered = now;
      break;
    case "translation":
      word.timesTranslationCorrect = (word.timesTranslationCorrect ?? 0) + 1;
      word.lastTranslationRemembered = now;
      break;
  }
  updateRememberFinal(word, ttsEnabled);
  word.lastReviewed = now;
  record(word, aspect, true, now);
}

export function markIncorrect(word, aspect) {
  word.timesSeen = (word.timesSeen ?? 0) + 1;
  word.lastReviewed = new Date();
  record(word, aspect, false, new Date());
}

/** Resets all spaced-repetition progress so the word counts as never remembered. */
export function resetMemory(word) {
  word.lastReviewed = null;
  word.lastWordRemembered = null;
  word.lastPronounciationRemembered = null;
  word.lastTranslationRemembered = null;
  word.timesSeen = 0;
  word.timesWordCorrect = 0;
  word.timesPronounciationCorrect = 0;
  word.timesTranslationCorrect = 0;
  word.memoryStats = null;
}

/** A fresh word document with the same defaults the iOS initializer uses. */
export function newWord({ term, translation, notes = "", partsOfSpeech = [], hiragana = null, pinyin = null }) {
  return {
    term,
    translation,
    notes,
    partsOfSpeech,
    partOfSpeech: null,
    hiragana,
    pinyin,
    audioPath: null,
    memoryStats: null,
    createdAt: new Date(),
    lastReviewed: null,
    lastWordRemembered: null,
    lastPronounciationRemembered: null,
    lastTranslationRemembered: null,
    timesSeen: 0,
    timesWordCorrect: 0,
    timesPronounciationCorrect: 0,
    timesTranslationCorrect: 0,
    remember_final: false,
  };
}
