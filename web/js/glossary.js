//
//  glossary.js
//  Retainic Web
//
//  The glossary model: a single-language reference deck whose entries are a
//  term and its definitions. Glossaries are independent of vocabulary lists —
//  separate documents, separate screens — and they review on a schedule of
//  their own: two methods instead of three (recalling the term and recalling
//  the definition), each finished after five correct recalls. There is no audio
//  and no translation language, so the pronunciation method never applies.
//
//  A term can mean several things, so an entry carries a list of definitions,
//  each with its own review schedule: shown a definition, you recall the term,
//  and every definition is a card of its own. The other direction — shown the
//  term, recall what it means — stays one card that reveals them all.
//
//    users/{uid}/glossaries/{glossaryId}                  -> glossary
//    users/{uid}/glossaries/{glossaryId}/entries/{entryId} -> entry
//

import { methodDue } from "./models.js";

/** The two things a glossary entry is practised on. `dailyAspect` is the word
 *  aspect its daily tally shares, so glossary practice shows up in Statistics
 *  alongside list practice. */
export const ASPECTS = [
  { id: "term", labelKey: "Term", dailyAspect: "spelling" },
  { id: "definition", labelKey: "Definition", dailyAspect: "translation" },
];

/** Which way round a glossary is practised. By default both: shown the term
 *  you recall what it means, and shown a definition you recall the term. A
 *  glossary can be set to the first direction alone, and then a term is
 *  finished once that one side is — its definitions are never a prompt, so
 *  waiting on them would leave the term stuck for good. */
export const BOTH_DIRECTIONS = "both";
export const TERM_TO_DEFINITION = "termToDefinition";

/** The direction a glossary is practised in. Glossaries saved before the
 *  setting existed have no field, and read as both. */
export function directionOf(glossary) {
  return glossary?.reviewDirection === TERM_TO_DEFINITION ? TERM_TO_DEFINITION : BOTH_DIRECTIONS;
}

/** A definition with no review progress yet. */
export function newDefinition(text) {
  return { text, timesCorrect: 0, lastRemembered: null };
}

/** The entry's definitions, each with its own schedule. Entries written before
 *  a term could mean several things stored one `definition` string, which reads
 *  as a single definition carrying the entry's definition counters. */
export function definitions(entry) {
  const stored = Array.isArray(entry.definitions) ? entry.definitions : [];
  if (stored.length) {
    return stored.map((d) => (typeof d === "string" ? newDefinition(d) : {
      text: d?.text ?? "",
      timesCorrect: d?.timesCorrect ?? 0,
      lastRemembered: d?.lastRemembered ?? null,
    }));
  }
  if (entry.definition) {
    return [{
      text: entry.definition,
      timesCorrect: entry.timesDefinitionCorrect ?? 0,
      lastRemembered: entry.lastDefinitionRemembered ?? null,
    }];
  }
  return [];
}

/** Just the text of each definition, for display and search. */
export function definitionTexts(entry) {
  return definitions(entry).map((d) => d.text);
}

/** The definitions as one line, for list rows and the legacy single field. */
export function joinedDefinitions(entry) {
  return definitionTexts(entry).join("; ");
}

/** Mirrors the definition list onto the fields that predate it: the joined
 *  text, the lowest per-definition count (what mastery waits on), and the most
 *  recent recall (what Statistics counts). Clients still reading a single
 *  definition — older installs, the stats screen — stay coherent. */
function syncLegacyFields(entry) {
  const defs = definitions(entry);
  entry.definition = defs.map((d) => d.text).join("; ");
  entry.timesDefinitionCorrect = defs.length ? Math.min(...defs.map((d) => d.timesCorrect)) : 0;
  const dates = defs.map((d) => d.lastRemembered).filter(Boolean).map((d) => +d);
  entry.lastDefinitionRemembered = dates.length ? new Date(Math.max(...dates)) : null;
}

// MARK: - The glossary schedule
//
// Glossaries run their own review algorithm rather than borrowing a word's. It
// is given the progress of the side being scheduled and returns, for the term
// and for the definition, how many days to wait before showing it again — or -1
// once that side is finished and never comes due again. A glossary can override
// it with its own Python (compiled in algorithm.js); with no override the
// built-in schedule below runs: five recalls of each side, at the gaps below.

const REVIEW_GAPS = [0, 1, 1, 2, 4];

/** How many correct recalls the built-in schedule needs to finish a side. */
export const REQUIRED_RECALLS = REVIEW_GAPS.length;

/** The built-in schedule, as a review function. */
export function defaultGlossaryReview(state) {
  const gap = (count) => (count < REVIEW_GAPS.length ? REVIEW_GAPS[count] : -1);
  return { term: gap(state.times_term), definition: gap(state.times_definition) };
}

let activeReview = defaultGlossaryReview;

/** Installs a compiled review override, or resets to the default when null. */
export function setActiveGlossaryAlgorithm(fn) {
  activeReview = fn || defaultGlossaryReview;
}

/** The state the review function sees. `definitionIndex` picks which
 *  definition's progress to pass; without one the entry is described by its
 *  least-practised definition, so mastery waits for all of them. */
function entryState(entry, definitionIndex = null) {
  const counts = definitions(entry).map((d) => d.timesCorrect);
  return {
    times_term: entry.timesTermCorrect ?? 0,
    times_definition: definitionIndex != null
      ? (counts[definitionIndex] ?? 0)
      : (counts.length ? Math.min(...counts) : 0),
  };
}

export function isTermDue(entry, now = new Date()) {
  return methodDue(activeReview(entryState(entry)).term, entry.lastTermRemembered, now);
}

/** Whether a definition is due. With no `definitionIndex`, whether any is. */
export function isDefinitionDue(entry, now = new Date(), definitionIndex = null) {
  const defs = definitions(entry);
  const due = (i) => methodDue(activeReview(entryState(entry, i)).definition, defs[i].lastRemembered, now);
  if (definitionIndex != null) return defs[definitionIndex] ? due(definitionIndex) : false;
  return defs.some((_, i) => due(i));
}

/** The indexes of the definitions due for review right now. */
export function dueDefinitionIndexes(entry, now = new Date()) {
  return definitions(entry).map((_, i) => i).filter((i) => isDefinitionDue(entry, now, i));
}

/** Whether the given aspect is due for review. */
export function isAspectDue(entry, aspect, now = new Date(), definitionIndex = null) {
  return aspect === "term" ? isTermDue(entry, now) : isDefinitionDue(entry, now, definitionIndex);
}

export function isRemembered(entry) {
  return entry.remember_final === true;
}

/** An entry is memorized once every side of it is finished — the algorithm
 *  says -1 (never again) for the term and for each definition. On the built-in
 *  schedule that means five recalls apiece, so a term that means five things
 *  isn't done until all five meanings are. Practised in one direction only,
 *  the term side is the whole of it: five recalls of what the term means and
 *  the entry is done. */
function updateRememberFinal(entry, direction) {
  const termFinished = activeReview(entryState(entry)).term < 0;
  if (direction === TERM_TO_DEFINITION) { entry.remember_final = termFinished; return; }
  const defs = definitions(entry);
  entry.remember_final = termFinished
    && defs.length > 0
    && defs.every((_, i) => activeReview(entryState(entry, i)).definition < 0);
}

/** Re-decides whether the entry counts as memorized under `direction`, for
 *  when a glossary's direction changes: the progress that was enough one way
 *  round may not be the other. Returns whether the answer moved. */
export function applyDirection(entry, direction) {
  const before = entry.remember_final === true;
  updateRememberFinal(entry, direction);
  return entry.remember_final !== before;
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
 *  entry the way `markCorrect` does for words. A definition recall advances
 *  only the definition that was practised. `direction` is the glossary's, and
 *  decides how much of the entry has to be finished for it to count as
 *  memorized. */
export function markCorrect(entry, aspect, definitionIndex = 0, direction = BOTH_DIRECTIONS) {
  const now = new Date();
  entry.timesSeen = (entry.timesSeen ?? 0) + 1;
  if (aspect === "term") {
    entry.timesTermCorrect = (entry.timesTermCorrect ?? 0) + 1;
    entry.lastTermRemembered = now;
  } else {
    const defs = definitions(entry);
    const definition = defs[definitionIndex];
    if (definition) {
      definition.timesCorrect += 1;
      definition.lastRemembered = now;
    }
    entry.definitions = defs;
    syncLegacyFields(entry);
  }
  updateRememberFinal(entry, direction);
  entry.lastReviewed = now;
  record(entry, aspect, true, now);
}

export function markIncorrect(entry, aspect) {
  const now = new Date();
  entry.timesSeen = (entry.timesSeen ?? 0) + 1;
  entry.lastReviewed = now;
  record(entry, aspect, false, now);
}

/** Replaces the entry's definitions with `texts`, keeping the review progress
 *  at each position: editing the wording of a definition leaves its schedule
 *  alone, a new one starts unlearned, and a removed one takes its progress
 *  with it. */
export function setDefinitions(entry, texts, direction = BOTH_DIRECTIONS) {
  const previous = definitions(entry);
  entry.definitions = texts.map((text, i) => ({
    text,
    timesCorrect: previous[i]?.timesCorrect ?? 0,
    lastRemembered: previous[i]?.lastRemembered ?? null,
  }));
  syncLegacyFields(entry);
  updateRememberFinal(entry, direction);
  return entry;
}

/** Resets all review progress so the entry counts as never remembered. */
export function resetMemory(entry) {
  entry.lastReviewed = null;
  entry.lastTermRemembered = null;
  entry.lastDefinitionRemembered = null;
  entry.timesSeen = 0;
  entry.timesTermCorrect = 0;
  entry.timesDefinitionCorrect = 0;
  entry.definitions = definitionTexts(entry).map(newDefinition);
  entry.memoryStats = null;
  entry.remember_final = false;
}

/** A fresh entry document, shaped for Firestore. Takes a list of definitions,
 *  or a single one for callers that only ever have the one. */
export function newEntry({ term, definitions: texts, definition = "", notes = "" }) {
  const entry = {
    term,
    definitions: [],
    definition: "",
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
  const list = (texts ?? [definition]).map((text) => String(text).trim()).filter(Boolean);
  entry.definitions = list.map(newDefinition);
  syncLegacyFields(entry);
  return entry;
}
