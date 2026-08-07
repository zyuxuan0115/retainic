import assert from "node:assert/strict";
import { test } from "node:test";

// csv.js pulls in i18n.js for the localized export headers, which reads browser
// globals at import time — stub them exactly as the translation test does.
const defineGlobal = (name, value) => Object.defineProperty(globalThis, name, {
  configurable: true,
  value,
  writable: true,
});
defineGlobal("navigator", { languages: ["en"], language: "en" });
defineGlobal("localStorage", { getItem: () => null, setItem: () => {} });
defineGlobal("document", { documentElement: { lang: "en" } });
defineGlobal("window", { dispatchEvent: () => {} });
defineGlobal("CustomEvent", class CustomEvent {});

const { csvEscape, parseCsv, wordsFromCsv } = await import("../js/csv.js");

test("parseCsv handles quotes, embedded separators, CRLF, and a BOM", () => {
  const text = '﻿一,"a, b","say ""hi"""\r\nmulti,"line\nbreak",\r\n';
  assert.deepEqual(parseCsv(text), [
    ["一", "a, b", 'say "hi"'],
    ["multi", "line\nbreak", ""],
  ]);
});

test("escaping round-trips back through the parser", () => {
  const fields = ["plain", 'has "quotes"', "has, comma", "has\nnewline", ""];
  const line = fields.map(csvEscape).join(",");
  assert.deepEqual(parseCsv(line), [fields]);
});

test("headerless rows are read in canonical column order", () => {
  const { words, skipped } = wordsFromCsv("猫,cat,a pet,noun;verb,,mao\n,orphan,,,,\n");
  assert.equal(skipped, 1); // the row with no term
  assert.equal(words.length, 1);
  assert.equal(words[0].term, "猫");
  assert.equal(words[0].translation, "cat");
  assert.equal(words[0].notes, "a pet");
  assert.deepEqual(words[0].partsOfSpeech, ["noun", "verb"]);
  assert.equal(words[0].pinyin, "mao");
  assert.equal(words[0].hiragana, null);
  assert.equal(words[0].remember_final, false);
});

test("a header row maps columns by name, in any order", () => {
  const { words } = wordsFromCsv("translation,word\ncat,猫\n");
  assert.equal(words.length, 1);
  assert.equal(words[0].term, "猫");
  assert.equal(words[0].translation, "cat");
});

test("a file exported by the app imports back, readings included", () => {
  // The exact shape downloadListCSV writes for a Japanese list, headers localized.
  const exported = "﻿単語,読み,翻訳,品詞,メモ\r\n猫,ねこ,cat,名詞,a pet\r\n";
  const { words } = wordsFromCsv(exported, "ja");
  assert.equal(words.length, 1);
  assert.equal(words[0].term, "猫");
  assert.equal(words[0].hiragana, "ねこ");
  assert.equal(words[0].pinyin, null);
  assert.equal(words[0].translation, "cat");
  assert.deepEqual(words[0].partsOfSpeech, ["noun"]); // localized label mapped back
  assert.equal(words[0].notes, "a pet");

  // The same single Reading column is a pinyin reading for a Chinese list.
  const zh = wordsFromCsv("Word,Reading,Translation\n猫,mao,cat\n", "zh");
  assert.equal(zh.words[0].pinyin, "mao");
  assert.equal(zh.words[0].hiragana, null);
});

test("parts of speech are read in any supported language", () => {
  const rows = "gato,cat,,Sustantivo\n猫,cat,,名词;动词\n고양이,cat,,명사\n犬,dog,,noun\n";
  const { words, skipped } = wordsFromCsv(rows);
  assert.equal(skipped, 0);
  assert.deepEqual(words.map((w) => w.partsOfSpeech), [
    ["noun"], ["noun", "verb"], ["noun"], ["noun"],
  ]);
});

test("rows that don't match the format are skipped, not half-imported", () => {
  // "pet" names no part of speech in any language, so that row is dropped.
  const { words, skipped } = wordsFromCsv("猫,cat,,pet\n犬,dog,,noun\n");
  assert.equal(skipped, 1);
  assert.deepEqual(words.map((w) => w.term), ["犬"]);

  // One bad label among good ones still invalidates the row.
  assert.equal(wordsFromCsv("猫,cat,,noun;pet\n").skipped, 1);

  // An empty part-of-speech cell is fine — it just means none were given.
  const none = wordsFromCsv("猫,cat,a pet,,,mao\n");
  assert.equal(none.skipped, 0);
  assert.deepEqual(none.words[0].partsOfSpeech, []);

  // Data past the last column the file names has nowhere to go.
  assert.equal(wordsFromCsv("猫,cat,a pet,noun,,mao,extra\n").skipped, 1);
  assert.equal(wordsFromCsv("word,translation\n猫,cat,a pet\n").skipped, 1);
  // Trailing empty fields are not "extra" data.
  assert.equal(wordsFromCsv("猫,cat,a pet,noun,,mao,\n").skipped, 0);
});

test("a data row is never mistaken for a header", () => {
  // "cat" names no column, so row one stays a word.
  const { words } = wordsFromCsv("word,cat\n猫,cat\n");
  assert.equal(words.length, 2);
  assert.equal(words[0].term, "word");
});

test("empty and blank-only files yield no words", () => {
  assert.deepEqual(wordsFromCsv(""), { words: [], skipped: 0 });
  assert.deepEqual(wordsFromCsv("\n,,\r\n"), { words: [], skipped: 0 });
});
