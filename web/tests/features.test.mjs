import assert from "node:assert/strict";
import { test } from "node:test";

import {
  factValues,
  isListDraftValid,
  markCorrect,
  newWord,
  recallPresentation,
  translationValues,
} from "../js/models.js";
import { memoryLapses, reviewWeight, weightedOrder } from "../js/review-order.js";

test("same-language lists are valid when both languages and a name are set", () => {
  assert.equal(isListDraftValid("Facts", "en", "en"), true);
  assert.equal(isListDraftValid("", "en", "en"), false);
  assert.equal(isListDraftValid("Facts", "", "en"), false);
});

test("multi-fact words prefer the plural field and preserve the legacy scalar", () => {
  assert.deepEqual(translationValues({ translation: "legacy" }), ["legacy"]);
  assert.deepEqual(
    translationValues({ translation: "legacy", translations: [" aquamarine ", "450nm", ""] }),
    ["aquamarine", "450nm"],
  );

  const word = newWord({ term: "blue", translations: ["aquamarine", "450nm"] });
  assert.equal(word.translation, "aquamarine");
  assert.deepEqual(word.translations, ["aquamarine", "450nm"]);
  assert.deepEqual(factValues(word), ["blue", "aquamarine", "450nm"]);
});

test("practice prompts one text fact and reveals every other fact", () => {
  const word = newWord({ term: "blue", translations: ["aquamarine", "450nm"] });

  assert.deepEqual(recallPresentation(word, 0), {
    prompt: "blue",
    answerTerm: null,
    answerFacts: ["aquamarine", "450nm"],
  });
  assert.deepEqual(recallPresentation(word, 1), {
    prompt: "aquamarine",
    answerTerm: "blue",
    answerFacts: ["450nm"],
  });
  assert.deepEqual(recallPresentation(word, 2), {
    prompt: "450nm",
    answerTerm: "blue",
    answerFacts: ["aquamarine"],
  });
  assert.deepEqual(recallPresentation(word, null).answerFacts, ["aquamarine", "450nm"]);
});

test("all related facts share the existing translation schedule", () => {
  const word = newWord({ term: "blue", translations: ["aquamarine", "450nm"] });
  markCorrect(word, "translation");

  assert.equal(word.timesTranslationCorrect, 1);
  assert.equal(word.memoryStats.translation.seen, 1);
  assert.equal(word.memoryStats.translation.timesRemembered, 1);
  assert.equal(Object.keys(word.memoryStats).length, 1);
});

test("lapses derive from aggregate stats and bias ordering without dropping items", () => {
  const repeatedlyForgotten = {
    memoryStats: { translation: { seen: 15, timesRemembered: 3 } },
  };
  const perfect = {
    memoryStats: { translation: { seen: 5, timesRemembered: 5 } },
  };

  assert.equal(memoryLapses(repeatedlyForgotten, "translation"), 12);
  assert.equal(reviewWeight(repeatedlyForgotten, "translation"), 10);
  assert.equal(reviewWeight(perfect, "translation"), 1);

  const items = [
    { id: "perfect", word: perfect },
    { id: "forgotten", word: repeatedlyForgotten },
  ];
  const ordered = weightedOrder(
    items,
    (item) => reviewWeight(item.word, "translation"),
    () => 0.5,
  );
  assert.deepEqual(ordered.map((item) => item.id), ["forgotten", "perfect"]);
  assert.deepEqual(new Set(ordered), new Set(items));
});
