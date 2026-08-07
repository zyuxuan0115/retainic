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
  // The built-in schedule waits a day after the first correct term recall.
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
  // The built-in schedule finishes at 8 term recalls + 10 definition recalls,
  // and glossary entries never carry the audio requirement words can.
  for (let i = 0; i < 8; i++) G.markCorrect(entry, "term");
  assert.equal(G.isRemembered(entry), false);
  for (let i = 0; i < 9; i++) G.markCorrect(entry, "definition");
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
