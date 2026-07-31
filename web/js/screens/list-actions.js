//
//  CSV export and list-sharing actions.
//  Retainic Web
//

import { el, toast } from "../dom.js";
import { t, preferredLanguage } from "../i18n.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";

/** Escapes one CSV field per RFC 4180: wrap in quotes when it contains a comma,
 *  quote, or newline, doubling any interior quotes. */
export function csvEscape(value) {
  const s = value == null ? "" : String(value);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** Fetches a list's words and downloads them as a UTF-8 .csv file. Columns:
 *  Word, Reading, Translation, Part of speech, Notes. */
export async function downloadListCSV(list) {
  let words;
  try { words = await Repo.fetchWords(authState.uid, list.id); }
  catch (e) { toast(Auth.friendlyMessage(e)); return; }

  // The Reading column (pinyin / hiragana) only applies to Chinese and Japanese.
  const hasReading = list.learningLanguage === "zh" || list.learningLanguage === "ja";
  const rows = [[
    t("Word"),
    ...(hasReading ? [t("Reading")] : []),
    t("Translation"), t("Part of speech"), t("Notes"),
  ]];
  for (const w of words) {
    rows.push([
      w.term || "",
      ...(hasReading ? [M.readingFor(w, list.learningLanguage) || ""] : []),
      M.translationValues(w).join("; "),
      M.partOfSpeechValues(w).map((p) => M.posLabel(p, preferredLanguage())).join("; "),
      w.notes || "",
    ]);
  }
  const csv = rows.map((r) => r.map(csvEscape).join(",")).join("\r\n");
  // Prepend a BOM so Excel opens UTF-8 (e.g. CJK text) correctly.
  const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
  const safeName = (list.name || "wordlist").replace(/[\\/:*?"<>|]+/g, "_").trim() || "wordlist";
  triggerDownload(blob, `${safeName}.csv`);
}

// MARK: - Share

/** Copies text to the clipboard, with a fallback for insecure contexts and
 *  older browsers. Resolves to whether the copy succeeded. */
async function copyToClipboard(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {}
  try {
    const ta = el("textarea", { value: text, style: "position:fixed;top:-1000px;opacity:0;" });
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    const ok = document.execCommand("copy");
    ta.remove();
    return ok;
  } catch { return false; }
}

/** Copies a list's unique ID to the clipboard so it can be shared with others. */
export async function shareListId(list) {
  const id = list.publicId;
  if (!id) { toast(t("This list isn't ready to share yet. Reopen it and try again.")); return; }
  const ok = await copyToClipboard(id);
  toast(ok
    ? t("Unique ID copied to clipboard. Share it with others so they can create the exact same wordlist.")
    : `${t("Couldn't copy automatically. Your list's unique ID is:")} ${id}`);
}

/** Downloads a Blob under the given filename via a temporary anchor. */
function triggerDownload(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = el("a", { href: url, download: filename });
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
