//
//  Vocabulary-list overview, trash, creation, and import flows.
//  Retainic Web
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, tn, tf, LANGUAGES, displayNameIn, preferredLanguage } from "../i18n.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { navBar, iconButton, spinner, emptyState, confirmDialog, formSection, pickerRow, icon, rectStackGlyph, errorState } from "../ui.js";

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

// MARK: - Trash screen

export async function TrashScreen(content) {
  let currentLists = [];
  const emptyBtn = iconButton(icon("delete_sweep", 24), () => confirmEmptyTrash(), { label: t("Empty Trash"), danger: true });
  emptyBtn.style.display = "none";
  content.appendChild(navBar(t("Trash"), { trailing: emptyBtn }));
  const body = el(".scroll");
  content.appendChild(body);
  body.appendChild(spinner(t("Loading…")));

  function confirmEmptyTrash() {
    if (!currentLists.length) return;
    confirmDialog({
      message: `${t("Permanently delete all lists in the Trash?")} ${t("This can't be undone.")}`,
      confirmLabel: t("Empty Trash"), workingLabel: t("Deleting…"), danger: true,
      // Non-interruptible: the dialog stays (and blocks) until every list is gone.
      onConfirm: async () => {
        for (const l of currentLists) await Repo.purgeList(authState.uid, l.id);
        await reload();
      },
    });
  }

  async function reload() {
    let lists = [];
    try { lists = await Repo.fetchTrashedLists(authState.uid); }
    catch (e) { clear(body); body.appendChild(errorState(e)); return; }
    currentLists = lists;
    emptyBtn.style.display = lists.length ? "" : "none";
    clear(body);
    if (lists.length === 0) {
      body.appendChild(emptyState(icon("delete", 46), t("Trash is Empty"),
        t("Deleted lists are kept here until you restore or permanently delete them.")));
      return;
    }
    const listEl = el(".list");
    for (const list of lists) {
      listEl.appendChild(el(".row", {},
        el(".row-lead", {}, rectStackGlyph()),
        el(".row-main", {},
          el(".row-title", {}, list.name),
          el(".row-sub", {}, tn("%lld words", list.wordCount ?? 0)),
        ),
        iconButton(icon("restore_from_trash", 22), async () => {
          try { await Repo.restoreList(authState.uid, list.id); reload(); }
          catch (err) { toast(Auth.friendlyMessage(err)); }
        }, { label: t("Restore") }),
        iconButton(icon("delete_forever", 22), () => {
          confirmDialog({
            message: `${t("Delete Forever")} “${list.name}”? ${t("This can't be undone.")}`,
            confirmLabel: t("Delete Forever"), workingLabel: t("Deleting…"), danger: true,
            // Let errors propagate so the dialog re-enables and toasts; on
            // success the dialog closes only after the list is fully purged.
            onConfirm: async () => {
              await Repo.purgeList(authState.uid, list.id);
              await reload();
            },
          });
        }, { label: t("Delete Forever"), danger: true }),
      ));
    }
    body.appendChild(listEl);
  }
  reload();
}

function presentNewListSheet(onCreated) {
  presentSheet((api) => {
    let mode = "create"; // or "import"

    // --- Create form ---
    let learning = "";
    let original = preferredLanguage();
    const name = el("input.field-input", { type: "text", placeholder: t("e.g. Kitchen vocabulary") });
    const learnSel = languageSelect(learning, t("Select…"), (v) => { learning = v; validate(); });
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
    // Create mode confirms with a checkmark; Import mode advances (→) to the
    // naming step. Keep the button's glyph and label in sync with the mode.
    function updateActionBtn() {
      const creating = mode === "create";
      clear(actionBtn);
      actionBtn.appendChild(icon(creating ? "check" : "arrow_forward", 24));
      const lbl = creating ? t("Create") : t("Import");
      actionBtn.title = lbl;
      actionBtn.setAttribute("aria-label", lbl);
    }
    updateActionBtn();

    const segCreate = el("button.seg.active", { onclick: () => setMode("create") }, t("Create new"));
    const segImport = el("button.seg", { onclick: () => setMode("import") }, t("Import by ID"));
    const seg = el(".segmented", {}, segCreate, segImport);

    function setMode(m) {
      if (mode === m) return;
      mode = m;
      const creating = m === "create";
      createForm.style.display = creating ? "" : "none";
      importForm.style.display = creating ? "none" : "";
      segCreate.classList.toggle("active", creating);
      segImport.classList.toggle("active", !creating);
      updateActionBtn();
      validate();
    }

    function validate() {
      let ok;
      if (mode === "create") {
        footer.textContent = "";
        ok = M.isListDraftValid(name.value, learning, original);
      } else {
        ok = idInput.value.trim().length > 0;
      }
      actionBtn.disabled = !ok;
      actionBtn.classList.toggle("disabled", !ok);
    }

    async function submit() {
      if (actionBtn.disabled) return;
      if (mode === "create") await doCreate();
      else await doLookup();
    }

    async function doCreate() {
      try {
        await Repo.createList(authState.uid, name.value.trim(), learning, original);
        api.close();
        onCreated();
      } catch (e) { toast(Auth.friendlyMessage(e)); }
    }

    async function doLookup() {
      const id = idInput.value.trim();
      actionBtn.disabled = true;
      actionBtn.classList.add("disabled");
      cancelBtn.disabled = true;
      cancelBtn.classList.add("disabled");
      try {
        const shared = await Repo.fetchSharedList(id);
        if (!shared) {
          importFooter.textContent = t("No wordlist found for that ID. Check it and try again.");
          cancelBtn.disabled = false;
          cancelBtn.classList.remove("disabled");
          validate();
          return;
        }
        api.close();
        presentImportNameSheet(shared, onCreated);
      } catch (e) {
        importFooter.textContent = Auth.friendlyMessage(e);
        cancelBtn.disabled = false;
        cancelBtn.classList.remove("disabled");
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
    const setAddIcon = (glyph) => { clear(addBtn); addBtn.appendChild(icon(glyph, 24)); };

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
      cancelBtn.disabled = locked;
      cancelBtn.classList.toggle("disabled", locked);
      addBtn.disabled = locked;
      addBtn.classList.toggle("disabled", locked);
    }

    async function finish() {
      if (addBtn.disabled) return;
      setLocked(true);
      setAddIcon("progress_activity"); // shows the copy is in progress
      const finalName = nameInput.value.trim() || src.name || t("Imported list");
      try {
        const newListId = await Repo.createList(
          authState.uid, finalName, src.learningLanguage || "", src.originalLanguage || "");
        for (const sw of shared.words) {
          const w = M.newWord({
            term: sw.term || "",
            translations: M.translationValues(sw),
            notes: sw.notes || "",
            partsOfSpeech: M.partOfSpeechValues(sw),
            hiragana: sw.hiragana || null,
            pinyin: sw.pinyin || null,
          });
          await Repo.addWord(authState.uid, newListId, w);
        }
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

function languageSelect(value, placeholder, onChange) {
  const sel = el("select.picker", { onchange: (e) => onChange(e.target.value) },
    el("option", { value: "" }, placeholder),
    ...LANGUAGES.map((l) => el("option", { value: l.code, selected: l.code === value }, displayNameIn(l.code))),
  );
  return sel;
}
