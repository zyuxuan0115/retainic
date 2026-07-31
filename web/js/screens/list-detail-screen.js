//
//  Word-list screen, selection flows, and list settings.
//  Retainic Web
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, tn, tf, preferredLanguage } from "../i18n.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { DEFAULT_ALGORITHM_CODE, useAlgorithm } from "../algorithm.js";
import { navBar, iconButton, spinner, emptyState, pronunciationButton, pickerRow, formSection, confirmDialog, icon, bookClosedGlyph, rectStackGlyph, errorState } from "../ui.js";
import { downloadListCSV, shareListId } from "./list-actions.js";
import { presentAlgorithmSheet } from "./algorithm-sheet.js";
import { presentWordSheet } from "./word-sheet.js";

// MARK: - List detail screen

export async function ListDetailScreen(content, list, { onBack, onPracticeChange }) {
  let words = [];
  let selecting = false;
  let selection = new Set();
  let searchText = "";
  let filter = "all"; // all | remembered | unremembered
  let listName = list.name;

  const header = el(".navbar-host");
  const body = el(".scroll");
  content.appendChild(header);
  content.appendChild(body);

  body.appendChild(spinner(t("Loading…")));
  try { words = await Repo.fetchWords(authState.uid, list.id); }
  catch (e) { clear(body); body.appendChild(errorState(e)); return; }
  // Match the scheduler to this list's algorithm so mastery recomputes (e.g.
  // when a recording is added/removed) use the right rule. Best-effort: a bad
  // snippet just leaves the default in place until the user fixes it.
  useAlgorithm(list.algorithmCode).catch(() => {});
  renderAll();

  // Keep the sidebar Practice action in sync with this list's words.
  function syncPractice() {
    onPracticeChange(words.length
      ? { cards: words.map((w) => ({ word: w, listId: list.id })), learningLanguage: list.learningLanguage || "", ttsEnabled: list.ttsEnabled === true, algorithmCode: list.algorithmCode || null }
      : null);
  }

  function filteredWords() {
    let r = words;
    if (filter === "remembered") r = r.filter(M.isRemembered);
    else if (filter === "unremembered") r = r.filter((w) => !M.isRemembered(w));
    const q = searchText.trim().toLowerCase();
    if (q) r = r.filter((w) => w.term.toLowerCase().includes(q) ||
      M.translationValues(w).some((fact) => fact.toLowerCase().includes(q)));
    return r;
  }

  function renderAll() {
    syncPractice();
    // Nav bar
    clear(header);
    const title = selecting
      ? (selection.size === 0 ? t("Select Words") : tn("%lld Selected", selection.size))
      : listName;
    let trailing;
    if (selecting) {
      const can = selection.size > 0;
      trailing = el(".navbar-actions", {},
        iconButton(icon("drive_file_move", 22), beginMove, { label: t("Move"), disabled: !can }),
        iconButton(icon("delete", 22), deleteSelected, { label: t("Delete"), danger: true, disabled: !can }),
        iconButton(icon("check", 22), endSelection, { label: t("Done") }),
      );
    } else {
      trailing = el(".navbar-actions", {},
        iconButton(icon("settings", 22), openListSettings, { label: t("Settings") }),
        iconButton(icon("add", 24), openAdd, { label: t("Add Word") }),
        words.length ? iconButton(icon("checklist", 22), beginSelection, { label: t("Select") }) : null,
      );
    }
    header.appendChild(navBar(title, {
      leading: selecting ? null : iconButton(icon("arrow_back", 22), onBack, { label: "Back" }),
      trailing,
    }));

    // Body
    clear(body);
    if (words.length === 0) {
      body.appendChild(emptyState(bookClosedGlyph(), t("No Words Yet"),
        tf("Add the words you're learning to “%@”.", listName),
        el("button.btn.primary", { onclick: openAdd }, t("Add Your First Word"))));
      return;
    }
    const search = el("input.search", { type: "search", placeholder: t("Search words"), value: searchText });
    search.addEventListener("input", () => { searchText = search.value; renderRows(); });
    body.appendChild(el(".search-wrap", {}, search));
    const rowsHost = el(".list", { id: "rows-host" });
    body.appendChild(rowsHost);
    renderRows();

    function renderRows() {
      const host = body.querySelector("#rows-host");
      clear(host);
      for (const w of filteredWords()) host.appendChild(wordRow(w));
    }
  }

  function wordRow(w) {
    const checked = selection.has(w.id);
    const posChips = M.partOfSpeechValues(w).map((p) =>
      el(".chip", {}, M.posLabel(p, preferredLanguage())));
    const audioBtn = pronunciationButton(w, list);
    const row = el(".row.word-row" + (selecting && checked ? ".selected" : ""), {
      onclick: () => {
        if (selecting) { toggleSelect(w.id); }
        else openEdit(w);
      },
    },
      selecting ? el(".select-dot" + (checked ? ".on" : ""), {}, checked ? icon("check", 16) : null) : null,
      el(".row-main", {},
        el(".word-top", {},
          el("span.word-term", {}, w.term),
          M.reading(w) ? el("span.word-reading", {}, M.reading(w)) : null,
          ...posChips,
        ),
        el(".row-sub", {}, M.translationValues(w).join(" • ")),
      ),
      audioBtn,
      !selecting ? el(".row-chevron", {}, icon("chevron_right", 22)) : null,
    );
    return row;
  }


  // Selection
  function beginSelection() { selecting = true; selection = new Set(); renderAll(); }
  function endSelection() { selecting = false; selection = new Set(); renderAll(); }
  function toggleSelect(id) {
    if (selection.has(id)) selection.delete(id); else selection.add(id);
    renderAll();
  }

  function deleteSelected() {
    const ids = new Set(selection);
    if (ids.size === 0) return;
    const message = ids.size === 1 ? t("Delete this word?") : tn("Delete %lld words?", ids.size);
    confirmDialog({
      message, confirmLabel: t("Delete"), danger: true,
      onConfirm: async () => {
        try {
          for (const id of ids) await Repo.deleteWord(authState.uid, list.id, id);
          words = words.filter((w) => !ids.has(w.id));
        } catch (e) { toast(Auth.friendlyMessage(e)); }
        endSelection();
      },
    });
  }

  async function beginMove() {
    let lists = [];
    try { lists = await Repo.fetchLists(authState.uid); } catch (e) { toast(Auth.friendlyMessage(e)); return; }
    const targets = lists.filter((o) => o.id !== list.id
      && o.learningLanguage === list.learningLanguage
      && o.originalLanguage === list.originalLanguage);
    presentMoveSheet(targets, selection.size, async (dest) => {
      const ids = new Set(selection);
      try {
        for (const w of words.filter((x) => ids.has(x.id)))
          await Repo.moveWord(authState.uid, list.id, dest.id, w);
        words = words.filter((w) => !ids.has(w.id));
      } catch (e) { toast(Auth.friendlyMessage(e)); }
      endSelection();
    });
  }

  // Add / edit
  function openAdd() {
    presentWordSheet({ list, word: null, onSaved: reload });
  }
  function openEdit(w) {
    presentWordSheet({ list, word: w, onSaved: reload });
  }
  async function reload() {
    try { words = await Repo.fetchWords(authState.uid, list.id); } catch (e) { toast(Auth.friendlyMessage(e)); }
    renderAll();
  }

  function openListSettings() {
    presentListSettingsSheet({
      name: listName,
      filter,
      ttsEnabled: list.ttsEnabled === true,
      onFilter: (f) => { filter = f; renderAll(); },
      onSetTTS: async (enabled) => {
        list.ttsEnabled = enabled;
        // Turning text-to-speech on adds the pronunciation requirement to every
        // word; turning it off drops it (the pronunciation count is kept, just
        // no longer required). Recompute and persist each word so "remembered"
        // status and filters reflect the new setting right away.
        for (const w of words) M.refreshMemorization(w, enabled);
        renderAll();
        try {
          await Repo.setListTTS(authState.uid, list.id, enabled);
          for (const w of words) await Repo.updateWord(authState.uid, list.id, w, { ttsEnabled: enabled });
        } catch (e) { toast(Auth.friendlyMessage(e)); }
      },
      onRename: async (newName) => {
        const trimmed = newName.trim();
        if (!trimmed) return;
        listName = trimmed;
        try { await Repo.renameList(authState.uid, list.id, trimmed); } catch (e) { toast(Auth.friendlyMessage(e)); }
        renderAll();
      },
      onReset: async () => {
        try {
          for (const w of words) { M.resetMemory(w); await Repo.updateWord(authState.uid, list.id, w); }
        } catch (e) { toast(Auth.friendlyMessage(e)); }
        renderAll();
      },
      onDownload: () => downloadListCSV(list),
      onShare: () => shareListId(list),
      onEditAlgorithm: () => {
        presentAlgorithmSheet({
          code: list.algorithmCode,
          onSave: async (newCode) => {
            const trimmed = newCode.trim();
            // Storing the unchanged default is the same as no override — keep
            // the field clear so those lists never load Pyodide.
            const store = (trimmed && trimmed !== DEFAULT_ALGORITHM_CODE.trim()) ? newCode : null;
            list.algorithmCode = store;
            try { await Repo.setListAlgorithm(authState.uid, list.id, store); }
            catch (e) { toast(Auth.friendlyMessage(e)); }
            syncPractice();
          },
        });
      },
      onTrash: async () => {
        try { await Repo.trashList(authState.uid, list.id); }
        catch (e) { toast(Auth.friendlyMessage(e)); return; }
        // The list is gone from the active set; return to the list overview.
        onBack();
      },
    });
  }

}

function presentMoveSheet(targets, count, onSelect) {
  presentSheet((api) => {
    let bodyContent;
    if (targets.length === 0) {
      bodyContent = emptyState(rectStackGlyph(), t("No Compatible Lists"),
        t("You need another list with the same learning and native language to move these words."));
    } else {
      bodyContent = el(".list", {}, ...targets.map((l) =>
        el(".row.tappable", { onclick: () => {
          confirmDialog({
            message: tf("Move %lld words to “%@”?", count, l.name), confirmLabel: t("Move"),
            onConfirm: () => { onSelect(l); api.close(); },
          });
        } },
          el(".row-lead", {}, rectStackGlyph()),
          el(".row-main", {}, el(".row-title", {}, l.name), el(".row-sub", {}, tn("%lld words", l.wordCount ?? 0))),
        )));
    }
    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, el("button.icon-btn", {
          onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
        }, icon("close", 24))),
        el(".sheet-title", {}, tn("Move %lld Words", count)),
        el(".sheet-side.trailing", {}),
      ),
      el(".scroll", {}, bodyContent),
    );
  });
}

function presentListSettingsSheet({ name, filter, ttsEnabled, onFilter, onSetTTS, onEditAlgorithm, onRename, onReset, onDownload, onShare, onTrash }) {
  presentSheet((api) => {
    const nameInput = el("input.field-input", { type: "text", value: name });
    const filterSel = el("select.picker", { onchange: (e) => onFilter(e.target.value) },
      el("option", { value: "all", selected: filter === "all" }, t("Show all")),
      el("option", { value: "remembered", selected: filter === "remembered" }, t("Show remembered only")),
      el("option", { value: "unremembered", selected: filter === "unremembered" }, t("Show unremembered only")),
    );
    const saveBtn = el("button.icon-btn", {
      onclick: () => { if (!saveBtn.disabled) { onRename(nameInput.value); api.close(); } },
      title: t("Save"), "aria-label": t("Save"),
    }, icon("check", 24));
    // Save is enabled only once the name is non-empty and differs from the
    // list's current name — nothing to save otherwise.
    function validateSave() {
      const trimmed = nameInput.value.trim();
      const changed = trimmed.length > 0 && trimmed !== name.trim();
      saveBtn.disabled = !changed;
      saveBtn.classList.toggle("disabled", !changed);
    }
    nameInput.addEventListener("input", validateSave);
    validateSave();
    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, el("button.icon-btn", {
          onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
        }, icon("close", 24))),
        el(".sheet-title", {}, t("List Settings")),
        el(".sheet-side.trailing", {}, saveBtn),
      ),
      el(".form", {},
        formSection(t("List name"), el(".form-card", {}, nameInput)),
        formSection(t("Show words"), el(".form-card", {}, pickerRow(t("Show words"), filterSel))),
        formSection(null,
          el(".form-card", {}, ttsToggleRow(ttsEnabled, onSetTTS)),
          el(".form-note", {}, t("Read words aloud with a synthesized voice when they have no recording."))),
        formSection(null,
          el(".form-card", {},
            el("button.form-action", {
              onclick: () => { api.close(); onEditAlgorithm(); },
            }, icon("code", 20), t("Edit review algorithm")),
          ),
          el(".form-note", {}, t("Write your own Python to schedule reviews and decide when a word is memorized."))),
        formSection(null,
          el(".form-card", {},
            el("button.form-action", {
              onclick: () => { onDownload(); api.close(); },
            }, icon("download", 20), t("Download CSV")),
          ),
          el(".form-note", {}, t("Save this list's words as a .csv file."))),
        formSection(null,
          el(".form-card", {},
            el("button.form-action", {
              onclick: () => onShare(),
            }, icon("share", 20), t("Share List")),
          ),
          el(".form-note", {}, t("Copies this list's unique ID so others can recreate it."))),
        formSection(null,
          el(".form-card", {},
            el("button.form-action.danger", {
              onclick: () => confirmDialog({
                message: t("Mark all words as not remembered?"),
                confirmLabel: t("Mark All as Not Remembered"), danger: true,
                onConfirm: () => { onReset(); api.close(); },
              }),
            }, icon("replay", 20), t("Mark all as not remembered")),
          ),
          el(".form-note", {}, t("Every word in this list will show up again in practice for all methods."))),
        formSection(null,
          el(".form-card", {},
            el("button.form-action.danger", {
              onclick: () => confirmDialog({
                message: `${t("Move to Trash")} “${name}”?`, confirmLabel: t("Move to Trash"), danger: true,
                onConfirm: () => { api.close(); onTrash(); },
              }),
            }, icon("delete", 20), t("Move to Trash")),
          )),
      ),
    );
  });
}

/** A labelled on/off switch for the list's text-to-speech setting, mirroring the
 *  toggle style used in the practice setup. Applies immediately via `onChange`. */
function ttsToggleRow(initial, onChange) {
  let on = initial === true;
  const sw = el(".switch" + (on ? ".on" : ""), {}, el(".knob"));
  sw.addEventListener("click", () => {
    on = !on;
    sw.classList.toggle("on", on);
    onChange(on);
  });
  return el(".toggle-row", {}, el("span", {}, t("Text-to-speech")), sw);
}
