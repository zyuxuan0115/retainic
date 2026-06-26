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
  const table = POS_LABELS[code] || POS_LABELS.en;
  return table[raw] || (raw.charAt(0).toUpperCase() + raw.slice(1));
}

// MARK: - Spaced-repetition schedules (must match FirestoreModels.swift)

export const MEMORIZED_BOX = 5;
const TRANSLATION_GAPS = [0, 1, 1, 1, 2, 2, 3, 4, 5, 10];
const WORD_GAPS = [0, 1, 1, 2, 3, 4, 6, 9];
const PRONUNCIATION_GAPS = [0, 1, 2, 3, 4, 6, 8];

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

/** Shared due check: due once the schedule's gap of days has passed (or never
 *  remembered), and not yet mastered (remembered as many times as steps). */
function isDue(count, last, gaps, now) {
  if (count >= gaps.length) return false;
  if (!last) return true;
  return daysBetween(last, now) >= gaps[count];
}

// MARK: - Word helpers (operate on plain word objects)

/** Selected parts of speech, reading the array field then the legacy single. */
export function partOfSpeechValues(word) {
  if (Array.isArray(word.partsOfSpeech) && word.partsOfSpeech.length) {
    return word.partsOfSpeech.filter((p) => p && p !== "unspecified");
  }
  if (word.partOfSpeech && word.partOfSpeech !== "unspecified") return [word.partOfSpeech];
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

export function isMemorized(word) {
  return (word.box ?? 1) >= MEMORIZED_BOX;
}

export function isRemembered(word) {
  return word.remember_final === true;
}

export function isTranslationDue(word, now = new Date()) {
  return isDue(word.timesTranslationCorrect ?? 0, word.lastTranslationRemembered, TRANSLATION_GAPS, now);
}

export function isWordDue(word, now = new Date()) {
  return isDue(word.timesWordCorrect ?? 0, word.lastWordRemembered, WORD_GAPS, now);
}

export function isPronunciationDue(word, now = new Date()) {
  return isDue(word.timesPronounciationCorrect ?? 0, word.lastPronounciationRemembered, PRONUNCIATION_GAPS, now);
}

/** Marks the word finally remembered once each mode has enough correct recalls. */
function updateRememberFinal(word) {
  const w = word.timesWordCorrect ?? 0;
  const tr = word.timesTranslationCorrect ?? 0;
  const pr = word.timesPronounciationCorrect ?? 0;
  const pronunciationOK = word.audioPath == null || pr >= 7;
  if (w >= 8 && tr >= 10 && pronunciationOK) word.remember_final = true;
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

/** Records a correct recall for the given aspect (mutates the word). */
export function markCorrect(word, aspect) {
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
  updateRememberFinal(word);
  word.box = Math.min((word.box ?? 1) + 1, 5);
  word.lastReviewed = now;
  record(word, aspect, true, now);
}

export function markIncorrect(word, aspect) {
  word.timesSeen = (word.timesSeen ?? 0) + 1;
  word.box = 1;
  word.lastReviewed = new Date();
  record(word, aspect, false, new Date());
}

/** Resets all spaced-repetition progress so the word counts as never remembered. */
export function resetMemory(word) {
  word.box = 1;
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
    box: 1,
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
