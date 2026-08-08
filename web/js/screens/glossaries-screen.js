//
//  Glossary overview and creation.
//  Retainic Web
//
//  A glossary is a single-language collection of terms and definitions, kept
//  entirely separate from vocabulary lists: its own dashboard, its own
//  documents (see repository.js), its own practice deck.
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, tn, tf, displayNameIn } from "../i18n.js";
import { entriesFromCsv } from "../csv.js";
import * as Repo from "../repository.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { navBar, iconButton, spinner, emptyState, formSection, pickerRow, languageSelect, icon, errorState } from "../ui.js";

/** The glyph a glossary is shown with, everywhere it is listed. */
export function glossaryGlyph(size = 24) {
  return icon("dictionary", size);
}

export async function GlossariesScreen(content, onOpenGlossary) {
  content.appendChild(navBar(t("My Glossaries"), {
    trailing: iconButton(icon("add", 24), () => presentNewGlossarySheet(reload), { label: t("New Glossary") }),
  }));
  const body = el(".scroll");
  content.appendChild(body);
  body.appendChild(spinner(t("Loading…")));

  async function reload() {
    let glossaries = [];
    try { glossaries = await Repo.fetchGlossaries(authState.uid); }
    catch (e) { clear(body); body.appendChild(errorState(e)); return; }
    clear(body);
    if (glossaries.length === 0) {
      body.appendChild(emptyState(glossaryGlyph(46), t("No Glossaries Yet"),
        t("Create your first glossary to collect terms and what they mean."),
        el("button.btn.primary", { onclick: () => presentNewGlossarySheet(reload) }, t("Create a Glossary"))));
      return;
    }
    const listEl = el(".list");
    for (const glossary of glossaries) {
      const language = glossary.language ? displayNameIn(glossary.language) : "";
      listEl.appendChild(el(".row.tappable", { onclick: () => onOpenGlossary(glossary) },
        el(".row-lead", {}, glossaryGlyph()),
        el(".row-main", {},
          el(".row-title", {}, glossary.name),
          el(".row-sub", {}, [tn("%lld terms", glossary.entryCount ?? 0), language].filter(Boolean).join(" · ")),
        ),
        el(".row-chevron", {}, icon("chevron_right", 22)),
      ));
    }
    body.appendChild(listEl);
  }
  reload();
}

/** New Glossary: an empty glossary, or one filled from a CSV file. Both create
 *  the glossary itself, so the name and language fields are shared. */
function presentNewGlossarySheet(onCreated) {
  presentSheet((api) => {
    let mode = "create"; // create | csv
    // A glossary is monolingual: terms and definitions are both written in this
    // one language, so there is no translation language to pick.
    let language = "";
    const name = el("input.field-input", { type: "text", placeholder: t("e.g. Legal terms") });
    const langSel = languageSelect(language, t("Select…"), (v) => { language = v; validate(); });
    const footer = el(".form-footer-error");
    name.addEventListener("input", validate);
    const createForm = el(".form", {},
      formSection(t("Glossary name"), el(".form-card", {}, name)),
      formSection(t("Language"),
        el(".form-card", {}, pickerRow(t("Terms are in"), langSel)),
        el(".form-note", {}, t("Terms and definitions are both written in this language.")),
        footer),
    );

    // --- CSV form (shown under the create form in "csv" mode) ---
    let csvText = null;
    let csvFileName = "";
    let csvEntries = [];
    const csvStatus = el(".form-note");
    const csvFooter = el(".form-footer-error");
    const fileInput = el("input", {
      type: "file", accept: ".csv,text/csv", style: "display:none", onchange: readChosenFile,
    });
    const csvForm = el(".form", { style: "display:none" },
      formSection(t("Terms file"),
        el(".form-card", {},
          el("button.form-action", { onclick: () => fileInput.click() },
            icon("upload_file", 22), el("span", {}, t("Choose file…"))),
        ),
        el(".form-note", {}, t("Columns, in order: term, definitions, notes. Separate several definitions with a semicolon, or repeat the term on another row. A header row is optional, and files exported from Retainic work as-is.")),
        csvStatus, csvFooter),
      fileInput);

    async function readChosenFile() {
      const file = fileInput.files && fileInput.files[0];
      // Clear the input so re-picking the same file after an error still fires.
      fileInput.value = "";
      if (!file) return;
      csvText = null;
      csvFileName = file.name;
      try { csvText = await file.text(); }
      catch { csvEntries = []; csvStatus.textContent = ""; csvFooter.textContent = t("Couldn't read that file."); validate(); return; }
      refreshCsv();
      validate();
    }

    /** Re-parses the chosen file and reports what it found. */
    function refreshCsv() {
      csvStatus.textContent = "";
      csvFooter.textContent = "";
      csvEntries = [];
      if (csvText == null) return;
      const { entries, skipped } = entriesFromCsv(csvText);
      csvEntries = entries;
      if (!entries.length) {
        csvFooter.textContent = t("No terms found in that file. Check it and try again.");
        return;
      }
      csvStatus.textContent = tf("Found %lld terms in “%@”.", entries.length, csvFileName)
        + (skipped ? " " + tn("Skipped %lld rows that don't match the format.", skipped) : "");
    }

    const createBtn = el("button.icon-btn", { onclick: submit, title: t("Create"), "aria-label": t("Create") }, icon("check", 24));
    const cancelBtn = el("button.icon-btn", {
      onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
    }, icon("close", 24));

    const segCreate = el("button.seg.active", { onclick: () => setMode("create") }, t("Create new"));
    const segCsv = el("button.seg", { onclick: () => setMode("csv") }, t("Import CSV"));
    const seg = el(".segmented", {}, segCreate, segCsv);

    function setMode(m) {
      if (mode === m) return;
      mode = m;
      // A CSV import creates a glossary too, so the create form stays visible
      // with the file picker beneath it.
      csvForm.style.display = m === "csv" ? "" : "none";
      segCreate.classList.toggle("active", m === "create");
      segCsv.classList.toggle("active", m === "csv");
      validate();
    }

    function validate() {
      const ok = Boolean(name.value.trim() && language) && (mode === "create" || csvEntries.length > 0);
      createBtn.disabled = !ok;
      createBtn.classList.toggle("disabled", !ok);
    }

    /** Locks the whole panel while a non-interruptible write runs. */
    function setBusy(busy) {
      api.setDismissible(!busy);
      for (const btn of [createBtn, cancelBtn]) {
        btn.disabled = busy;
        btn.classList.toggle("disabled", busy);
      }
    }

    async function submit() {
      if (createBtn.disabled) return;
      if (mode === "create") {
        try {
          await Repo.createGlossary(authState.uid, name.value.trim(), language);
          api.close();
          onCreated();
        } catch (e) { toast(Auth.friendlyMessage(e)); }
        return;
      }
      // CSV: create the glossary, then write its terms. The panel stays locked
      // until every term is stored.
      const finalName = name.value.trim();
      const entries = csvEntries;
      setBusy(true);
      clear(createBtn);
      createBtn.appendChild(icon("progress_activity", 24)); // shows the import is in progress
      try {
        const glossaryId = await Repo.createGlossary(authState.uid, finalName, language);
        await Repo.addEntries(authState.uid, glossaryId, entries);
        api.close();
        onCreated();
        toast(tf("Imported “%@” with %lld terms.", finalName, entries.length));
      } catch (e) {
        csvFooter.textContent = Auth.friendlyMessage(e);
        setBusy(false);
        clear(createBtn);
        createBtn.appendChild(icon("check", 24));
        validate();
      }
    }

    setTimeout(validate, 0);
    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, cancelBtn),
        el(".sheet-title", {}, t("New Glossary")),
        el(".sheet-side.trailing", {}, createBtn),
      ),
      el(".form", {}, formSection(null, seg)),
      createForm,
      csvForm,
    );
  });
}
