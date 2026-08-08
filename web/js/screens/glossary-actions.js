//
//  Glossary CSV export.
//  Retainic Web
//
//  The counterpart to the CSV import in glossaries-screen.js: what this writes,
//  that reads back unchanged.
//

import { toast, triggerDownload } from "../dom.js";
import { t } from "../i18n.js";
import { csvEscape, DEFINITION_SEPARATOR } from "../csv.js";
import * as Repo from "../repository.js";
import * as G from "../glossary.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";

/** Fetches a glossary's terms and downloads them as a UTF-8 .csv file.
 *  Columns: Term, Definitions, Notes — a term that means several things puts
 *  them all in the one cell, separated by semicolons. */
export async function downloadGlossaryCSV(glossary) {
  let entries;
  try { entries = await Repo.fetchEntries(authState.uid, glossary.id); }
  catch (e) { toast(Auth.friendlyMessage(e)); return; }

  const rows = [[t("Term"), t("Definitions"), t("Notes")]];
  for (const entry of entries) {
    rows.push([
      entry.term || "",
      G.definitionTexts(entry).join(DEFINITION_SEPARATOR),
      entry.notes || "",
    ]);
  }
  const csv = rows.map((r) => r.map(csvEscape).join(",")).join("\r\n");
  // Prepend a BOM so Excel opens UTF-8 (e.g. CJK text) correctly.
  const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
  const safeName = (glossary.name || "glossary").replace(/[\\/:*?"<>|]+/g, "_").trim() || "glossary";
  triggerDownload(blob, `${safeName}.csv`);
}
