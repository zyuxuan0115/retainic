//
//  Vocabulary-list overview, creation, and import flows.
//  Retainic Web
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, tn, tf, preferredLanguage } from "../i18n.js";
import { wordsFromCsv, nameFromFile } from "../csv.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { navBar, iconButton, spinner, emptyState, formSection, pickerRow, languageSelect, icon, setButtonBusy, rectStackGlyph, errorState } from "../ui.js";

// MARK: - Lists screen

export async function ListsScreen(content, onOpenList) {
  content.appendChild(navBar(t("My Lists"), {
    trailing: iconButton(icon("add", 24), () => presentNewListSheet(reload), { label: t("New List") }),
  }));
  const body = el(".scroll");
  content.appendChild(body);
  body.appendChild(spinner(t("Loading…")));

  async function reload() {
    let lists = [];
    try { lists = await Repo.fetchLists(authState.uid); }
    catch (e) { clear(body); body.appendChild(errorState(e)); return; }
    clear(body);
    if (lists.length === 0) {
      body.appendChild(emptyState(rectStackGlyph(), t("No Lists Yet"),
        t("Create your first vocabulary list to start adding words."),
        el("button.btn.primary", { onclick: () => presentNewListSheet(reload) }, t("Create a List"))));
      return;
    }
    const listEl = el(".list");
    for (const list of lists) {
      listEl.appendChild(el(".row.tappable", { onclick: () => onOpenList(list) },
        el(".row-lead", {}, rectStackGlyph()),
        el(".row-main", {},
          el(".row-title", {}, list.name),
          el(".row-sub", {}, tn("%lld words", list.wordCount ?? 0)),
        ),
        el(".row-chevron", {}, icon("chevron_right", 22)),
      ));
    }
    body.appendChild(listEl);
  }
  reload();
}

function presentNewListSheet(onCreated) {
  presentSheet((api) => {
    let mode = "create"; // or "csv" or "import"

    // --- Create form (also the name/languages step of a CSV import) ---
    let learning = "";
    let original = preferredLanguage();
    const name = el("input.field-input", { type: "text", placeholder: t("e.g. Kitchen vocabulary") });
    // Re-read the file on a language change: it decides whether an exported
    // "Reading" column is a pinyin or a hiragana reading.
    const learnSel = languageSelect(learning, t("Select…"), (v) => { learning = v; refreshCsv(); validate(); });
    const origSel = languageSelect(original, t("Select…"), (v) => { original = v; validate(); });
    const footer = el(".form-footer-error");
    name.addEventListener("input", validate);
    const createForm = el(".form", {},
      formSection(t("List name"), el(".form-card", {}, name)),
      formSection(t("Languages"),
        el(".form-card", {},
          pickerRow(t("I'm learning"), learnSel),
          pickerRow(t("Translated into"), origSel),
        ), footer),
    );

    // --- CSV form (shown under the create form in "csv" mode) ---
    let csvText = null;
    let csvFileName = "";
    let csvWords = [];
    const csvStatus = el(".form-note");
    // Names the chosen file in place of the "Choose file…" prompt.
    const fileLabel = el("span.file-name", {}, t("Choose file…"));
    const csvFooter = el(".form-footer-error");
    const fileInput = el("input", {
      type: "file", accept: ".csv,text/csv", style: "display:none", onchange: readChosenFile,
    });
    const csvForm = el(".form", { style: "display:none" },
      formSection(t("Words file"),
        el(".form-card", {},
          el("button.form-action", { onclick: () => fileInput.click() },
            icon("upload_file", 22), fileLabel),
        ),
        el(".form-note", {}, t("Columns, in order: word, translation, notes, part of speech, hiragana, pinyin. A header row is optional, and files exported from Retainic work as-is.")),
        csvStatus, csvFooter),
      fileInput);

    async function readChosenFile() {
      const file = fileInput.files && fileInput.files[0];
      // Clear the input so re-picking the same file after an error still fires.
      fileInput.value = "";
      if (!file) return;
      csvText = null;
      csvFileName = file.name;
      fileLabel.textContent = file.name;
      suggestName(file.name);
      try { csvText = await file.text(); }
      catch { csvWords = []; csvStatus.textContent = ""; csvFooter.textContent = t("Couldn't read that file."); validate(); return; }
      refreshCsv();
      validate();
    }

    // The name the file suggested, so picking another file replaces it — but a
    // name the user typed themselves is never overwritten.
    let suggestedName = null;
    function suggestName(fileName) {
      const suggestion = nameFromFile(fileName);
      if (!suggestion) return;
      if (name.value.trim() && name.value !== suggestedName) return;
      name.value = suggestion;
      suggestedName = suggestion;
    }

    /** Re-parses the chosen file and reports what it found. */
    function refreshCsv() {
      csvStatus.textContent = "";
      csvFooter.textContent = "";
      csvWords = [];
      if (csvText == null) return;
      const { words, skipped } = wordsFromCsv(csvText, learning);
      csvWords = words;
      if (!words.length) {
        csvFooter.textContent = t("No words found in that file. Check it and try again.");
        return;
      }
      csvStatus.textContent = tf("Found %lld words in “%@”.", words.length, csvFileName)
        + (skipped ? " " + tn("Skipped %lld rows that don't match the format.", skipped) : "");
    }

    // --- Import form ---
    const idInput = el("input.field-input", { type: "text", placeholder: t("Paste the unique ID"), autocapitalize: "off", spellcheck: false });
    const importFooter = el(".form-footer-error");
    idInput.addEventListener("input", () => { importFooter.textContent = ""; validate(); });
    const importForm = el(".form", { style: "display:none" },
      formSection(t("Unique ID"),
        el(".form-card", {}, idInput),
        el(".form-note", {}, t("Enter the unique ID someone shared with you to add a copy of their wordlist.")),
        importFooter),
    );

    const actionBtn = el("button.icon-btn", { onclick: submit }, icon("check", 24));
    const cancelBtn = el("button.icon-btn", {
      onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
    }, icon("close", 24));
    // The create and CSV modes confirm with a checkmark; Import by ID advances
    // (→) to the naming step. Keep the button's glyph and label in sync.
    function updateActionBtn() {
      const creating = mode !== "import";
      clear(actionBtn);
      actionBtn.classList.remove("busy"); // back from the turning glyph, if it was showing
      actionBtn.appendChild(icon(creating ? "check" : "arrow_forward", 24));
      const lbl = creating ? t("Create") : t("Import");
      actionBtn.title = lbl;
      actionBtn.setAttribute("aria-label", lbl);
    }
    updateActionBtn();

    const segCreate = el("button.seg.active", { onclick: () => setMode("create") }, t("Create new"));
    const segCsv = el("button.seg", { onclick: () => setMode("csv") }, t("Import CSV"));
    const segImport = el("button.seg", { onclick: () => setMode("import") }, t("Import by ID"));
    const seg = el(".segmented", {}, segCreate, segCsv, segImport);
    const segments = [[segCreate, "create"], [segCsv, "csv"], [segImport, "import"]];

    function setMode(m) {
      if (mode === m) return;
      mode = m;
      // A CSV import creates a list, so it needs the name and languages too:
      // the create form stays visible with the file picker beneath it.
      createForm.style.display = m === "import" ? "none" : "";
      csvForm.style.display = m === "csv" ? "" : "none";
      importForm.style.display = m === "import" ? "" : "none";
      for (const [btn, key] of segments) btn.classList.toggle("active", m === key);
      updateActionBtn();
      validate();
    }

    /** Whether the shared name/languages fields are filled in, showing the
     *  same-language error underneath when they aren't. */
    function validateCreateFields() {
      const same = learning !== "" && learning === original;
      footer.textContent = same ? t("The two languages must be different.") : "";
      return Boolean(name.value.trim() && learning && original && !same);
    }

    function validate() {
      let ok;
      if (mode === "import") ok = idInput.value.trim().length > 0;
      else ok = validateCreateFields() && (mode === "create" || csvWords.length > 0);
      actionBtn.disabled = !ok;
      actionBtn.classList.toggle("disabled", !ok);
    }

    /** Locks the whole panel while a non-interruptible write runs: no field,
     *  mode or button inside it can be touched until the import finishes. */
    function setBusy(busy) {
      api.setBusy(busy);
      for (const btn of [actionBtn, cancelBtn]) {
        btn.disabled = busy;
        btn.classList.toggle("disabled", busy);
      }
    }

    async function submit() {
      if (actionBtn.disabled) return;
      if (mode === "create") await doCreate();
      else if (mode === "csv") await doCreateFromCsv();
      else await doLookup();
    }

    async function doCreate() {
      try {
        await Repo.createList(authState.uid, name.value.trim(), learning, original);
        api.close();
        onCreated();
      } catch (e) { toast(Auth.friendlyMessage(e)); }
    }

    /** Creates the list, then writes the words parsed from the chosen file.
     *  Like the by-ID import, the panel locks until every word is stored. */
    async function doCreateFromCsv() {
      const finalName = name.value.trim();
      const words = csvWords;
      setBusy(true);
      setButtonBusy(actionBtn, true); // a turning glyph while the words are written
      try {
        const listId = await Repo.createList(authState.uid, finalName, learning, original);
        await Repo.addWords(authState.uid, listId, words);
        api.close();
        onCreated();
        toast(tf("Imported “%@” with %lld words.", finalName, words.length));
      } catch (e) {
        csvFooter.textContent = Auth.friendlyMessage(e);
        setBusy(false);
        updateActionBtn();
        validate();
      }
    }

    async function doLookup() {
      const id = idInput.value.trim();
      setBusy(true);
      try {
        const shared = await Repo.fetchSharedList(id);
        if (!shared) {
          importFooter.textContent = t("No wordlist found for that ID. Check it and try again.");
          setBusy(false);
          validate();
          return;
        }
        api.close();
        presentImportNameSheet(shared, onCreated);
      } catch (e) {
        importFooter.textContent = Auth.friendlyMessage(e);
        setBusy(false);
        validate();
      }
    }

    setTimeout(validate, 0);
    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, cancelBtn),
        el(".sheet-title", {}, t("New List")),
        el(".sheet-side.trailing", {}, actionBtn),
      ),
      el(".form", {}, formSection(null, seg)),
      createForm,
      csvForm,
      importForm,
    );
  });
}

/** Import step 2: confirm a name for the copy (defaulting to the original), then
 *  create the list and copy its words. Shown after a successful ID lookup. */
function presentImportNameSheet(shared, onCreated) {
  presentSheet((api) => {
    // A click outside never closes this panel — importing writes many words and
    // must not be interrupted. Exit is only via Cancel (before the copy starts).
    api.setDismissible(false);

    const src = shared.list;
    const nameInput = el("input.field-input", { type: "text", value: src.name || "" });
    const footer = el(".form-footer-error");
    nameInput.addEventListener("input", validate);
    const addBtn = el("button.icon-btn", { onclick: finish, title: t("Add"), "aria-label": t("Add") }, icon("check", 24));
    const cancelBtn = el("button.icon-btn", { onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel") }, icon("close", 24));
    const setAddIcon = (glyph) => {
      clear(addBtn);
      addBtn.classList.remove("busy"); // back from the turning glyph, if it was showing
      addBtn.appendChild(icon(glyph, 24));
    };

    function validate() {
      if (importing) return;
      const ok = nameInput.value.trim().length > 0;
      addBtn.disabled = !ok;
      addBtn.classList.toggle("disabled", !ok);
    }

    // While the copy runs, lock the panel completely: no Cancel and a disabled
    // Add button, so the import can't be interrupted midway.
    let importing = false;
    function setLocked(locked) {
      importing = locked;
      // Nothing in the panel — the name field included — can be touched while
      // the copy runs. Unlocking after a failure restores the panel but not the
      // click-outside dismissal: this sheet never had it.
      api.setBusy(locked);
      api.setDismissible(false);
      cancelBtn.disabled = locked;
      cancelBtn.classList.toggle("disabled", locked);
      addBtn.disabled = locked;
      addBtn.classList.toggle("disabled", locked);
    }

    async function finish() {
      if (addBtn.disabled) return;
      setLocked(true);
      setButtonBusy(addBtn, true); // a turning glyph while the words are copied
      const finalName = nameInput.value.trim() || src.name || t("Imported list");
      try {
        const newListId = await Repo.createList(
          authState.uid, finalName, src.learningLanguage || "", src.originalLanguage || "");
        await Repo.addWords(authState.uid, newListId, shared.words.map((sw) => M.newWord({
          term: sw.term || "",
          translation: sw.translation || "",
          notes: sw.notes || "",
          partsOfSpeech: M.partOfSpeechValues(sw),
          hiragana: sw.hiragana || null,
          pinyin: sw.pinyin || null,
        })));
        api.close();
        onCreated();
        toast(tf("Imported “%@” with %lld words.", finalName, shared.words.length));
      } catch (e) {
        footer.textContent = Auth.friendlyMessage(e);
        setAddIcon("check");
        setLocked(false);
        validate();
      }
    }

    setTimeout(validate, 0);
    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, cancelBtn),
        el(".sheet-title", {}, t("New List")),
        el(".sheet-side.trailing", {}, addBtn),
      ),
      el(".form", {},
        el(".center-state", {},
          el(".empty-icon", {}, icon("check_circle", 44)),
          el("h2", {}, t("Import successful")),
          el("p", {}, tn("Found a wordlist with %lld words. Name your copy below.", shared.words.length))),
        formSection(t("List name"), el(".form-card", {}, nameInput), footer),
      ),
    );
  });
}
