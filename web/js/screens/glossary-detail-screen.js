//
//  Glossary entry list, selection, and glossary settings.
//  Retainic Web
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, tn, tf } from "../i18n.js";
import * as Repo from "../repository.js";
import * as G from "../glossary.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { navBar, iconButton, spinner, emptyState, confirmDialog, formSection, pickerRow, icon, errorState } from "../ui.js";
import { glossaryGlyph } from "./glossaries-screen.js";
import { presentEntrySheet } from "./entry-sheet.js";

export async function GlossaryDetailScreen(content, glossary, { onBack, onPracticeChange }) {
  let entries = [];
  let selecting = false;
  let selection = new Set();
  let searchText = "";
  let filter = "all"; // all | remembered | unremembered
  let glossaryName = glossary.name;

  const header = el(".navbar-host");
  const body = el(".scroll");
  content.appendChild(header);
  content.appendChild(body);

  body.appendChild(spinner(t("Loading…")));
  try { entries = await Repo.fetchEntries(authState.uid, glossary.id); }
  catch (e) { clear(body); body.appendChild(errorState(e)); return; }
  renderAll();

  // Keep the sidebar Practice action in sync with this glossary's entries.
  function syncPractice() {
    onPracticeChange(entries.length
      ? { kind: "glossary", cards: entries.map((e) => ({ entry: e, glossaryId: glossary.id })), language: glossary.language || "" }
      : null);
  }

  function filteredEntries() {
    let r = entries;
    if (filter === "remembered") r = r.filter(G.isRemembered);
    else if (filter === "unremembered") r = r.filter((e) => !G.isRemembered(e));
    const q = searchText.trim().toLowerCase();
    if (q) r = r.filter((e) => e.term.toLowerCase().includes(q) || e.definition.toLowerCase().includes(q));
    return r;
  }

  function renderAll() {
    syncPractice();
    // Nav bar
    clear(header);
    const title = selecting
      ? (selection.size === 0 ? t("Select Terms") : tn("%lld Selected", selection.size))
      : glossaryName;
    let trailing;
    if (selecting) {
      const can = selection.size > 0;
      trailing = el(".navbar-actions", {},
        iconButton(icon("delete", 22), deleteSelected, { label: t("Delete"), danger: true, disabled: !can }),
        iconButton(icon("check", 22), endSelection, { label: t("Done") }),
      );
    } else {
      trailing = el(".navbar-actions", {},
        iconButton(icon("settings", 22), openGlossarySettings, { label: t("Settings") }),
        iconButton(icon("add", 24), openAdd, { label: t("Add Term") }),
        entries.length ? iconButton(icon("checklist", 22), beginSelection, { label: t("Select") }) : null,
      );
    }
    header.appendChild(navBar(title, {
      leading: selecting ? null : iconButton(icon("arrow_back", 22), onBack, { label: "Back" }),
      trailing,
    }));

    // Body
    clear(body);
    if (entries.length === 0) {
      body.appendChild(emptyState(glossaryGlyph(46), t("No Terms Yet"),
        tf("Add the terms you want to remember to “%@”.", glossaryName),
        el("button.btn.primary", { onclick: openAdd }, t("Add Your First Term"))));
      return;
    }
    const search = el("input.search", { type: "search", placeholder: t("Search terms"), value: searchText });
    search.addEventListener("input", () => { searchText = search.value; renderRows(); });
    body.appendChild(el(".search-wrap", {}, search));
    const rowsHost = el(".list", { id: "rows-host" });
    body.appendChild(rowsHost);
    renderRows();

    function renderRows() {
      const host = body.querySelector("#rows-host");
      clear(host);
      for (const entry of filteredEntries()) host.appendChild(entryRow(entry));
    }
  }

  function entryRow(entry) {
    const checked = selection.has(entry.id);
    return el(".row.word-row" + (selecting && checked ? ".selected" : ""), {
      onclick: () => {
        if (selecting) toggleSelect(entry.id);
        else openEdit(entry);
      },
    },
      selecting ? el(".select-dot" + (checked ? ".on" : ""), {}, checked ? icon("check", 16) : null) : null,
      el(".row-main", {},
        el(".word-top", {}, el("span.word-term", {}, entry.term)),
        el(".row-sub", {}, entry.definition),
      ),
      !selecting ? el(".row-chevron", {}, icon("chevron_right", 22)) : null,
    );
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
    const message = ids.size === 1 ? t("Delete this term?") : tn("Delete %lld terms?", ids.size);
    confirmDialog({
      message, confirmLabel: t("Delete"), danger: true,
      onConfirm: async () => {
        try {
          for (const id of ids) await Repo.deleteEntry(authState.uid, glossary.id, id);
          entries = entries.filter((e) => !ids.has(e.id));
        } catch (e) { toast(Auth.friendlyMessage(e)); }
        endSelection();
      },
    });
  }

  // Add / edit
  function openAdd() {
    presentEntrySheet({ glossary, entry: null, onSaved: reload });
  }
  function openEdit(entry) {
    presentEntrySheet({ glossary, entry, onSaved: reload });
  }
  async function reload() {
    try { entries = await Repo.fetchEntries(authState.uid, glossary.id); }
    catch (e) { toast(Auth.friendlyMessage(e)); }
    renderAll();
  }

  function openGlossarySettings() {
    presentGlossarySettingsSheet({
      name: glossaryName,
      filter,
      onFilter: (f) => { filter = f; renderAll(); },
      onRename: async (newName) => {
        const trimmed = newName.trim();
        if (!trimmed) return;
        glossaryName = trimmed;
        try { await Repo.renameGlossary(authState.uid, glossary.id, trimmed); }
        catch (e) { toast(Auth.friendlyMessage(e)); }
        renderAll();
      },
      onReset: async () => {
        try {
          for (const entry of entries) {
            G.resetMemory(entry);
            await Repo.updateEntry(authState.uid, glossary.id, entry);
          }
        } catch (e) { toast(Auth.friendlyMessage(e)); }
        renderAll();
      },
      onTrash: async () => {
        try { await Repo.trashGlossary(authState.uid, glossary.id); }
        catch (e) { toast(Auth.friendlyMessage(e)); return; }
        // The glossary is gone from the active set; return to the overview.
        onBack();
      },
    });
  }
}

function presentGlossarySettingsSheet({ name, filter, onFilter, onRename, onReset, onTrash }) {
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
    // glossary's current name — nothing to save otherwise.
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
        el(".sheet-title", {}, t("Glossary Settings")),
        el(".sheet-side.trailing", {}, saveBtn),
      ),
      el(".form", {},
        formSection(t("Glossary name"), el(".form-card", {}, nameInput)),
        formSection(t("Show terms"), el(".form-card", {}, pickerRow(t("Show terms"), filterSel))),
        formSection(null,
          el(".form-card", {},
            el("button.form-action.danger", {
              onclick: () => confirmDialog({
                message: t("Mark all terms as not remembered?"),
                confirmLabel: t("Mark All as Not Remembered"), danger: true,
                onConfirm: () => { onReset(); api.close(); },
              }),
            }, icon("replay", 20), t("Mark all as not remembered")),
          ),
          el(".form-note", {}, t("Every term in this glossary will show up again in practice."))),
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
