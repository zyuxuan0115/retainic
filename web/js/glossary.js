//
//  glossary.js
//  Retainic Web
//
//  The glossary model: a single-language reference deck whose entries are a
//  term and its definition. Glossaries are independent of vocabulary lists —
//  separate documents, separate screens — but they practise on the same
//  spaced-repetition engine (models.js), with two methods instead of three:
//  recalling the term and recalling the definition. There is no audio and no
//  translation language, so the pronunciation method never applies.
//
//    users/{uid}/glossaries/{glossaryId}                  -> glossary
//    users/{uid}/glossaries/{glossaryId}/entries/{entryId} -> entry
//

import { methodDue, reviewSchedule } from "./models.js";

/** The two things a glossary entry is practised on. `dailyAspect` is the word
 *  aspect its daily tally shares, so glossary practice shows up in Statistics
 *  alongside list practice. */
export const ASPECTS = [
  { id: "term", labelKey: "Term", dailyAspect: "spelling" },
  { id: "definition", labelKey: "Definition", dailyAspect: "translation" },
];

/** The state the review algorithm sees for an entry. The algorithm is written
 *  against words, so the term maps onto its "word" method and the definition
 *  onto its "translation" one; with no audio, `masteredTotal` comes back
 *  without the pronunciation requirement. */
function entryState(entry) {
  return {
    times_word: entry.timesTermCorrect ?? 0,
    times_translation: entry.timesDefinitionCorrect ?? 0,
    times_pronunciation: 0,
    has_audio: false,
  };
}

export function isTermDue(entry, now = new Date()) {
  return methodDue(reviewSchedule(entryState(entry)).word, entry.lastTermRemembered, now);
}

export function isDefinitionDue(entry, now = new Date()) {
  return methodDue(reviewSchedule(entryState(entry)).translation, entry.lastDefinitionRemembered, now);
}

/** Whether the given aspect is due for review. */
export function isAspectDue(entry, aspect, now = new Date()) {
  return aspect === "term" ? isTermDue(entry, now) : isDefinitionDue(entry, now);
}

export function isRemembered(entry) {
  return entry.remember_final === true;
}

/** An entry is memorized once its two correct-counts together reach the
 *  algorithm's mastery total. */
function updateRememberFinal(entry) {
  const s = entryState(entry);
  entry.remember_final = s.times_word + s.times_translation >= reviewSchedule(s).masteredTotal;
}

function record(entry, aspect, correct, now) {
  const stats = entry.memoryStats || {};
  const stat = stats[aspect] || { seen: 0, timesRemembered: 0, lastRemembered: null };
  stat.seen += 1;
  if (correct) {
    stat.timesRemembered += 1;
    stat.lastRemembered = now;
  }
  stats[aspect] = stat;
  entry.memoryStats = stats;
}

/** Records a correct recall of `aspect` ("term" | "definition"), mutating the
 *  entry the way `markCorrect` does for words. */
export function markCorrect(entry, aspect) {
  const now = new Date();
  entry.timesSeen = (entry.timesSeen ?? 0) + 1;
  if (aspect === "term") {
    entry.timesTermCorrect = (entry.timesTermCorrect ?? 0) + 1;
    entry.lastTermRemembered = now;
  } else {
    entry.timesDefinitionCorrect = (entry.timesDefinitionCorrect ?? 0) + 1;
    entry.lastDefinitionRemembered = now;
  }
  updateRememberFinal(entry);
  entry.lastReviewed = now;
  record(entry, aspect, true, now);
}

export function markIncorrect(entry, aspect) {
  const now = new Date();
  entry.timesSeen = (entry.timesSeen ?? 0) + 1;
  entry.lastReviewed = now;
  record(entry, aspect, false, now);
}

/** Resets all review progress so the entry counts as never remembered. */
export function resetMemory(entry) {
  entry.lastReviewed = null;
  entry.lastTermRemembered = null;
  entry.lastDefinitionRemembered = null;
  entry.timesSeen = 0;
  entry.timesTermCorrect = 0;
  entry.timesDefinitionCorrect = 0;
  entry.memoryStats = null;
  entry.remember_final = false;
}

/** A fresh entry document, shaped for Firestore. */
export function newEntry({ term, definition, notes = "" }) {
  return {
    term,
    definition,
    notes,
    createdAt: new Date(),
    lastReviewed: null,
    lastTermRemembered: null,
    lastDefinitionRemembered: null,
    timesSeen: 0,
    timesTermCorrect: 0,
    timesDefinitionCorrect: 0,
    memoryStats: null,
    remember_final: false,
  };
}
