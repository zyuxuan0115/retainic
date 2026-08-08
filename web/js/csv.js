//
//  csv.js
//  Retainic Web
//
//  RFC 4180 escaping, parsing, and word mapping shared by the list CSV export
//  (screens/list-actions.js) and the create-from-CSV flow (screens/lists-screen.js).
//

import { LANGUAGES, t } from "./i18n.js";
import { newWord, posKey } from "./models.js";
import { newEntry } from "./glossary.js";

/** Escapes one CSV field per RFC 4180: wrap in quotes when it contains a comma,
 *  quote, or newline, doubling any interior quotes. */
export function csvEscape(value) {
  const s = value == null ? "" : String(value);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** Splits CSV text into rows of unescaped fields. Handles quoted fields (with
 *  doubled quotes), commas and newlines inside them, LF/CRLF line endings, and
 *  a leading UTF-8 BOM — which the app's own export writes for Excel. */
export function parseCsv(text) {
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (quoted) {
      if (ch !== '"') { field += ch; continue; }
      if (src[i + 1] === '"') { field += '"'; i++; continue; }
      quoted = false;
      continue;
    }
    if (ch === '"' && field === "") { quoted = true; continue; }
    if (ch === ",") { row.push(field); field = ""; continue; }
    if (ch === "\r" || ch === "\n") {
      if (ch === "\r" && src[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
      continue;
    }
    field += ch;
  }
  if (field !== "" || row.length) { row.push(field); rows.push(row); }
  return rows;
}

/** A name to suggest for what a chosen file imports into: the file's name
 *  without its .csv extension, or "" when nothing usable is left. Both import
 *  sheets offer this so the name field is filled in after picking a file. */
export function nameFromFile(fileName) {
  return String(fileName ?? "").trim().replace(/\.csv$/i, "").trim();
}

// MARK: - CSV → words

/** The column order assumed for a file with no header row. */
const COLUMNS = ["term", "translation", "notes", "partsOfSpeech", "hiragana", "pinyin"];

/** Header spellings understood for each column, beyond its canonical name. */
const ALIASES = {
  term: ["word"],
  notes: ["note"],
  partsOfSpeech: ["part of speech", "parts of speech", "partofspeech"],
  // Not a word field of its own: the export writes a single "Reading" column,
  // which is a pinyin or hiragana reading depending on the list's language.
  reading: ["reading"],
};

/** The localized header labels `downloadListCSV` writes, per column. */
const EXPORTED = {
  "Word": "term",
  "Translation": "translation",
  "Notes": "notes",
  "Part of speech": "partsOfSpeech",
  "Reading": "reading",
};

/** What one kind of file looks like: the column order assumed without a header
 *  row, columns only a header can name, the extra spellings each column answers
 *  to, and the localized headers this app's own export writes. `lookup` is
 *  built on first use. */
const WORD_SCHEMA = {
  columns: COLUMNS, headerOnly: ["reading"], aliases: ALIASES, exported: EXPORTED, lookup: null,
};

function normalize(value) {
  return String(value).trim().toLowerCase().replace(/\s+/g, " ");
}

/** Header label → column for a schema, covering the canonical names, their
 *  aliases, and the exported headers in every supported interface language. */
function headerLookup(schema) {
  if (schema.lookup) return schema.lookup;
  const names = new Map();
  for (const field of [...schema.columns, ...schema.headerOnly]) names.set(normalize(field), field);
  for (const [field, aliases] of Object.entries(schema.aliases)) {
    for (const alias of aliases) names.set(normalize(alias), field);
  }
  for (const language of LANGUAGES) {
    for (const [key, field] of Object.entries(schema.exported)) {
      names.set(normalize(t(key, language.code)), field);
    }
  }
  schema.lookup = names;
  return names;
}

/** The columns named by a header row, or null when the row isn't one. A row
 *  counts as a header only if every filled cell names a known column and one of
 *  them is the term — so a data row starting with a real word is never eaten. */
function headerFields(row, schema) {
  const lookup = headerLookup(schema);
  const cells = row.map(normalize);
  const fields = cells.map((cell) => (cell ? lookup.get(cell) ?? null : null));
  if (cells.some((cell, i) => cell && !fields[i])) return null;
  return fields.includes("term") ? fields : null;
}

/** The rows of a file that hold data, dropping the blank ones. */
function dataRows(text) {
  return parseCsv(text).filter((row) => row.some((field) => field.trim() !== ""));
}

/** Reads one row's cell for `field`, or "" when the file has no such column. */
function cellReader(row, fields) {
  return (field) => {
    const index = fields.indexOf(field);
    return index < 0 ? "" : (row[index] ?? "").trim();
  };
}

/** Parts of speech from one cell: labels in any supported language (or their
 *  canonical keys) separated by semicolons, slashes, or pipes — so "名詞" and
 *  "Sustantivo" read the same as "noun". Null when a piece names no part of
 *  speech at all, which marks the whole row as malformed. */
function partsOfSpeechFrom(raw) {
  const parts = [];
  for (const piece of String(raw).split(/[;/|]/)) {
    if (!piece.trim()) continue;
    const key = posKey(piece);
    if (!key) return null;
    if (!parts.includes(key)) parts.push(key);
  }
  return parts;
}

/** Reads CSV text into new word objects ready for `Repo.addWord`.
 *
 *  Columns are taken positionally in `COLUMNS` order — term, translation,
 *  notes, part of speech, hiragana, pinyin — unless the file starts with a
 *  header row, in which case they're matched by name. That also covers the
 *  files this app exports, whose headers are localized and whose single
 *  "Reading" column is read as pinyin or hiragana according to
 *  `learningLanguage`.
 *
 *  A row that doesn't fit that shape is skipped rather than half-imported, and
 *  the skipped rows are counted: rows with no term, rows whose part-of-speech
 *  cell holds something that isn't a part of speech in any supported language,
 *  and rows with data in a column the file doesn't name. */
export function wordsFromCsv(text, learningLanguage = "") {
  const rows = dataRows(text);
  if (!rows.length) return { words: [], skipped: 0 };

  const header = headerFields(rows[0], WORD_SCHEMA);
  const fields = header ?? COLUMNS;
  const words = [];
  let skipped = 0;

  for (const row of rows.slice(header ? 1 : 0)) {
    const cell = cellReader(row, fields);
    const term = cell("term");
    if (!term) { skipped++; continue; }
    // Content past the last known column (or under a blank header) means the
    // row has more fields than the format defines — don't guess at it.
    if (row.some((value, i) => !fields[i] && value.trim() !== "")) { skipped++; continue; }
    const partsOfSpeech = partsOfSpeechFrom(cell("partsOfSpeech"));
    if (!partsOfSpeech) { skipped++; continue; }
    const reading = cell("reading");
    words.push(newWord({
      term,
      translation: cell("translation"),
      notes: cell("notes"),
      partsOfSpeech,
      hiragana: cell("hiragana") || (learningLanguage === "ja" ? reading : "") || null,
      pinyin: cell("pinyin") || (learningLanguage === "zh" ? reading : "") || null,
    }));
  }
  return { words, skipped };
}

// MARK: - CSV → glossary entries

/** The column order assumed for a glossary file with no header row. */
const ENTRY_COLUMNS = ["term", "definitions", "notes"];

const ENTRY_SCHEMA = {
  columns: ENTRY_COLUMNS,
  headerOnly: [],
  aliases: {
    definitions: ["definition", "meaning", "meanings", "what it means"],
    notes: ["note"],
  },
  // The localized headers `downloadGlossaryCSV` writes. "Definition" is here
  // too so a file exported before a term could mean several things still reads.
  exported: { "Term": "term", "Definitions": "definitions", "Definition": "definitions", "Notes": "notes" },
  lookup: null,
};

/** The separator between definitions inside one cell, and what the glossary
 *  export joins them with. */
export const DEFINITION_SEPARATOR = "; ";

/** The definitions in one cell: several meanings separated by semicolons or
 *  pipes, blank pieces dropped. */
function definitionsFrom(raw) {
  return String(raw).split(/[;|]/).map((piece) => piece.trim()).filter(Boolean);
}

/** Reads CSV text into new entry objects ready for `Repo.addEntries`.
 *
 *  Columns are taken positionally in `ENTRY_COLUMNS` order — term, definitions,
 *  notes — unless the file starts with a header row, in which case they're
 *  matched by name, including the localized headers this app's own export
 *  writes.
 *
 *  A term that means several things can be written either way: as one cell of
 *  definitions separated by semicolons (what the export writes), or as one row
 *  per definition — rows that repeat a term are merged into a single entry
 *  holding all of its definitions, keeping the first notes given.
 *
 *  A row that doesn't fit that shape is skipped rather than half-imported, and
 *  the skipped rows are counted: rows with no term, rows with no definition,
 *  and rows with data in a column the file doesn't name. */
export function entriesFromCsv(text) {
  const rows = dataRows(text);
  if (!rows.length) return { entries: [], skipped: 0 };

  const header = headerFields(rows[0], ENTRY_SCHEMA);
  const fields = header ?? ENTRY_COLUMNS;
  const byTerm = new Map();
  const drafts = [];
  let skipped = 0;

  for (const row of rows.slice(header ? 1 : 0)) {
    const cell = cellReader(row, fields);
    const term = cell("term");
    if (!term) { skipped++; continue; }
    // Content past the last known column (or under a blank header) means the
    // row has more fields than the format defines — don't guess at it.
    if (row.some((value, i) => !fields[i] && value.trim() !== "")) { skipped++; continue; }
    const definitions = definitionsFrom(cell("definitions"));
    if (!definitions.length) { skipped++; continue; }
    const notes = cell("notes");

    const existing = byTerm.get(term.toLowerCase());
    if (existing) {
      // The same term again is another thing it means, not another entry.
      for (const definition of definitions) {
        if (!existing.definitions.includes(definition)) existing.definitions.push(definition);
      }
      if (!existing.notes) existing.notes = notes;
      continue;
    }
    const draft = { term, definitions, notes };
    byTerm.set(term.toLowerCase(), draft);
    drafts.push(draft);
  }
  return { entries: drafts.map((draft) => newEntry(draft)), skipped };
}
