//
//  csv.js
//  Retainic Web
//
//  RFC 4180 escaping, parsing, and word mapping shared by the list CSV export
//  (screens/list-actions.js) and the create-from-CSV flow (screens/lists-screen.js).
//

import { LANGUAGES, t } from "./i18n.js";
import { newWord, posKey } from "./models.js";

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

function normalize(value) {
  return String(value).trim().toLowerCase().replace(/\s+/g, " ");
}

let headerNames = null;

/** Header label → column, covering the canonical names, their aliases, and the
 *  exported headers in every supported interface language. */
function headerLookup() {
  if (headerNames) return headerNames;
  headerNames = new Map();
  for (const field of [...COLUMNS, "reading"]) headerNames.set(normalize(field), field);
  for (const [field, aliases] of Object.entries(ALIASES)) {
    for (const alias of aliases) headerNames.set(normalize(alias), field);
  }
  for (const language of LANGUAGES) {
    for (const [key, field] of Object.entries(EXPORTED)) {
      headerNames.set(normalize(t(key, language.code)), field);
    }
  }
  return headerNames;
}

/** The columns named by a header row, or null when the row isn't one. A row
 *  counts as a header only if every filled cell names a known column and one of
 *  them is the term — so a data row starting with a real word is never eaten. */
function headerFields(row) {
  const lookup = headerLookup();
  const cells = row.map(normalize);
  const fields = cells.map((cell) => (cell ? lookup.get(cell) ?? null : null));
  if (cells.some((cell, i) => cell && !fields[i])) return null;
  return fields.includes("term") ? fields : null;
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
  const rows = parseCsv(text).filter((row) => row.some((field) => field.trim() !== ""));
  if (!rows.length) return { words: [], skipped: 0 };

  const header = headerFields(rows[0]);
  const fields = header ?? COLUMNS;
  const words = [];
  let skipped = 0;

  for (const row of rows.slice(header ? 1 : 0)) {
    const cell = (field) => {
      const index = fields.indexOf(field);
      return index < 0 ? "" : (row[index] ?? "").trim();
    };
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
