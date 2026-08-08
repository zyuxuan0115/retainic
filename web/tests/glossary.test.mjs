import assert from "node:assert/strict";
import { test } from "node:test";

// glossary.js only reaches into models.js for the review algorithm, so it
// imports cleanly outside a browser.
import * as G from "../js/glossary.js";

const daysAgo = (n) => new Date(Date.now() - n * 86400000);

test("a new entry starts unlearned and due for both methods", () => {
  const entry = G.newEntry({ term: "estoppel", definition: "a bar to asserting a claim" });
  assert.equal(entry.term, "estoppel");
  assert.equal(entry.remember_final, false);
  assert.equal(G.isRemembered(entry), false);
  assert.equal(G.isTermDue(entry), true);
  assert.equal(G.isDefinitionDue(entry), true);
});

test("a correct answer schedules that method and leaves the other alone", () => {
  const entry = G.newEntry({ term: "estoppel", definition: "a bar to asserting a claim" });
  G.markCorrect(entry, "term");
  assert.equal(entry.timesTermCorrect, 1);
  assert.equal(entry.timesSeen, 1);
  // The glossary schedule waits a day after the first correct term recall.
  assert.equal(G.isTermDue(entry), false);
  assert.equal(G.isTermDue(entry, new Date(Date.now() + 86400000)), true);
  // The definition has its own schedule and is still waiting.
  assert.equal(G.isDefinitionDue(entry), true);
  assert.equal(entry.timesDefinitionCorrect, 0);
});

test("a wrong answer counts as seen but doesn't advance the schedule", () => {
  const entry = G.newEntry({ term: "laches", definition: "unreasonable delay" });
  entry.lastTermRemembered = daysAgo(30);
  entry.timesTermCorrect = 1;
  G.markIncorrect(entry, "term");
  assert.equal(entry.timesTermCorrect, 1);
  assert.equal(entry.timesSeen, 1);
  assert.equal(entry.memoryStats.term.seen, 1);
  assert.equal(entry.memoryStats.term.timesRemembered, 0);
  assert.equal(G.isTermDue(entry), true);
});

test("an entry is memorized once both methods are finished", () => {
  const entry = G.newEntry({ term: "novation", definition: "replacing a contract party" });
  // The glossary schedule finishes each side after five correct recalls.
  assert.equal(G.REQUIRED_RECALLS, 5);
  for (let i = 0; i < G.REQUIRED_RECALLS; i++) G.markCorrect(entry, "term");
  assert.equal(G.isRemembered(entry), false);
  for (let i = 0; i < G.REQUIRED_RECALLS - 1; i++) G.markCorrect(entry, "definition");
  assert.equal(G.isRemembered(entry), false);
  G.markCorrect(entry, "definition");
  assert.equal(G.isRemembered(entry), true);
  // Finished methods never come due again.
  assert.equal(G.isTermDue(entry, new Date(Date.now() + 365 * 86400000)), false);
  assert.equal(G.isDefinitionDue(entry, new Date(Date.now() + 365 * 86400000)), false);

  G.resetMemory(entry);
  assert.equal(G.isRemembered(entry), false);
  assert.equal(entry.timesTermCorrect, 0);
  assert.equal(entry.timesDefinitionCorrect, 0);
  assert.equal(G.isTermDue(entry), true);
});

test("isAspectDue routes to the method the practice screen asks for", () => {
  const entry = G.newEntry({ term: "tort", definition: "a civil wrong" });
  G.markCorrect(entry, "term");
  assert.equal(G.isAspectDue(entry, "term"), false);
  assert.equal(G.isAspectDue(entry, "definition"), true);
  assert.deepEqual(G.ASPECTS.map((a) => a.id), ["term", "definition"]);
});

test("each definition is scheduled on its own", () => {
  const entry = G.newEntry({ term: "bank", definitions: ["a financial institution", "the side of a river"] });
  assert.deepEqual(G.definitionTexts(entry), ["a financial institution", "the side of a river"]);
  // Every definition is a card of its own, so both start out due.
  assert.deepEqual(G.dueDefinitionIndexes(entry), [0, 1]);

  G.markCorrect(entry, "definition", 1);
  assert.equal(entry.definitions[1].timesCorrect, 1);
  assert.equal(entry.definitions[0].timesCorrect, 0);
  assert.deepEqual(G.dueDefinitionIndexes(entry), [0]);
  // The entry as a whole still has something due today.
  assert.equal(G.isDefinitionDue(entry), true);
  assert.equal(G.isDefinitionDue(entry, new Date(), 1), false);
});

test("mastery waits for every definition", () => {
  const entry = G.newEntry({ term: "bank", definitions: ["a financial institution", "the side of a river"] });
  for (let i = 0; i < G.REQUIRED_RECALLS; i++) G.markCorrect(entry, "term");
  for (let i = 0; i < G.REQUIRED_RECALLS; i++) G.markCorrect(entry, "definition", 0);
  // One definition is finished; the other has never been recalled.
  assert.equal(G.isRemembered(entry), false);
  assert.deepEqual(G.dueDefinitionIndexes(entry), [1]);
  for (let i = 0; i < G.REQUIRED_RECALLS; i++) G.markCorrect(entry, "definition", 1);
  assert.equal(G.isRemembered(entry), true);
  assert.deepEqual(G.dueDefinitionIndexes(entry), []);
});

test("the five showings of a side follow the schedule's gaps", () => {
  const entry = G.newEntry({ term: "laches", definitions: ["unreasonable delay"] });
  const day = 86400000;
  // Nothing is due again until that side's gap has passed: 0, 1, 1, 2, then 4
  // days. A recall on the day it comes due keeps the schedule moving.
  const gaps = [0, 1, 1, 2, 4];
  let at = Date.now();
  for (const wait of gaps) {
    at += wait * day;
    assert.equal(G.isTermDue(entry, new Date(at)), true);
    assert.equal(G.isDefinitionDue(entry, new Date(at), 0), true);
    G.markCorrect(entry, "term");
    G.markCorrect(entry, "definition", 0);
  }
  // Five recalls each: both sides are finished and never come due again.
  assert.equal(G.isRemembered(entry), true);
  assert.equal(G.isTermDue(entry, new Date(at + 365 * day)), false);
  assert.equal(G.isDefinitionDue(entry, new Date(at + 365 * day)), false);
});

test("an entry stored with a single definition reads as a list of one", () => {
  // Documents written before a term could mean several things.
  const legacy = {
    term: "estoppel",
    definition: "a bar to asserting a claim",
    timesDefinitionCorrect: 3,
    lastDefinitionRemembered: daysAgo(30),
  };
  assert.deepEqual(G.definitionTexts(legacy), ["a bar to asserting a claim"]);
  assert.equal(G.isDefinitionDue(legacy), true);

  // Practising it migrates the entry, keeping the progress it already had.
  G.markCorrect(legacy, "definition", 0);
  assert.equal(legacy.definitions.length, 1);
  assert.equal(legacy.definitions[0].timesCorrect, 4);
  assert.equal(legacy.timesDefinitionCorrect, 4);
});

test("editing definitions keeps the progress at each position", () => {
  const entry = G.newEntry({ term: "bank", definitions: ["a financial institution", "the side of a river"] });
  G.markCorrect(entry, "definition", 0);
  G.setDefinitions(entry, ["a place that keeps money", "the side of a river", "a row of switches"]);
  assert.equal(entry.definitions[0].timesCorrect, 1);
  assert.equal(entry.definitions[2].timesCorrect, 0);
  // The fields older clients read follow the list: the joined text, the
  // weakest definition's count, and the most recent recall.
  assert.equal(entry.definition, "a place that keeps money; the side of a river; a row of switches");
  assert.equal(entry.timesDefinitionCorrect, 0);

  G.resetMemory(entry);
  assert.deepEqual(entry.definitions.map((d) => d.timesCorrect), [0, 0, 0]);
  assert.deepEqual(G.definitionTexts(entry).length, 3);
});

test("a glossary can schedule on its own algorithm", () => {
  // What a compiled Python override hands back: days until each side is due
  // again, -1 once it's finished. This one asks for two recalls a week apart.
  G.setActiveGlossaryAlgorithm((state) => ({
    term: state.times_term < 2 ? [0, 7][state.times_term] : -1,
    definition: state.times_definition < 2 ? [0, 7][state.times_definition] : -1,
  }));
  try {
    const entry = G.newEntry({ term: "bank", definitions: ["money", "river"] });
    G.markCorrect(entry, "term");
    // The override's gap, not the built-in one day.
    assert.equal(G.isTermDue(entry, new Date(Date.now() + 6 * 86400000)), false);
    assert.equal(G.isTermDue(entry, new Date(Date.now() + 7 * 86400000)), true);

    // Mastery follows the algorithm too: two recalls a side finishes the entry,
    // where the built-in schedule would have wanted five.
    G.markCorrect(entry, "term");
    for (let i = 0; i < 2; i++) { G.markCorrect(entry, "definition", 0); G.markCorrect(entry, "definition", 1); }
    assert.equal(G.isRemembered(entry), true);
    assert.deepEqual(G.dueDefinitionIndexes(entry), []);
  } finally {
    G.setActiveGlossaryAlgorithm(null);
  }
});

test("clearing the override puts the built-in schedule back", () => {
  G.setActiveGlossaryAlgorithm(() => ({ term: -1, definition: -1 }));
  G.setActiveGlossaryAlgorithm(null);
  const entry = G.newEntry({ term: "tort", definitions: ["a civil wrong"] });
  for (let i = 0; i < G.REQUIRED_RECALLS - 1; i++) G.markCorrect(entry, "term");
  assert.equal(G.isRemembered(entry), false);
  assert.deepEqual(G.defaultGlossaryReview({ times_term: 5, times_definition: 0 }), { term: -1, definition: 0 });
});
