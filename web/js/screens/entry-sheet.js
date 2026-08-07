//
//  Add and edit glossary entry flow.
//  Retainic Web
//

import { el, presentSheet, toast } from "../dom.js";
import { t, displayNameIn } from "../i18n.js";
import * as Repo from "../repository.js";
import * as G from "../glossary.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { icon, formSection, confirmDialog } from "../ui.js";

export function presentEntrySheet({ glossary, entry, onSaved }) {
  const isEditing = entry != null;

  presentSheet((api) => {
    const term = el("input.field-input", { type: "text", value: entry?.term || "", placeholder: t("Term") });
    const definition = el("textarea.field-input", { rows: 3, placeholder: t("What it means") }, entry?.definition || "");
    const notes = el("textarea.field-input", { rows: 3, placeholder: t("Example sentence or memory hint") }, entry?.notes || "");
    const errorEl = el(".form-footer-error");
    const saveBtn = el("button.icon-btn", { onclick: save, title: t("Save"), "aria-label": t("Save") }, icon("check", 24));

    // When editing, Save stays disabled until something actually changes.
    function hasChanges() {
      if (!isEditing) return true;
      return term.value.trim() !== (entry.term || "")
        || definition.value.trim() !== (entry.definition || "")
        || notes.value.trim() !== (entry.notes || "");
    }
    function validate() {
      const ok = term.value.trim() && definition.value.trim() && hasChanges();
      saveBtn.disabled = !ok;
      saveBtn.classList.toggle("disabled", !ok);
    }
    [term, definition, notes].forEach((i) => i.addEventListener("input", validate));

    async function save() {
      if (saveBtn.disabled) return;
      saveBtn.disabled = true;
      try {
        if (isEditing) {
          await Repo.updateEntry(authState.uid, glossary.id, {
            ...entry,
            term: term.value.trim(),
            definition: definition.value.trim(),
            notes: notes.value.trim(),
          });
        } else {
          await Repo.addEntry(authState.uid, glossary.id, G.newEntry({
            term: term.value.trim(),
            definition: definition.value.trim(),
            notes: notes.value.trim(),
          }));
        }
        api.close();
        onSaved();
      } catch (e) {
        errorEl.textContent = Auth.friendlyMessage(e);
        saveBtn.disabled = false;
      }
    }

    function deleteThisEntry() {
      confirmDialog({
        message: t("Delete this term?"), confirmLabel: t("Delete"), danger: true,
        onConfirm: async () => {
          try {
            await Repo.deleteEntry(authState.uid, glossary.id, entry.id);
            api.close();
            onSaved();
          } catch (e) { toast(Auth.friendlyMessage(e)); }
        },
      });
    }

    setTimeout(validate, 0);
    const termTitle = glossary.language ? displayNameIn(glossary.language) : t("Term");

    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, isEditing ? null : el("button.icon-btn", {
          onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
        }, icon("close", 24))),
        el(".sheet-title", {}, isEditing ? t("Edit Term") : t("New Term")),
        el(".sheet-side.trailing", {}, saveBtn),
      ),
      el(".form", {},
        formSection(termTitle, el(".form-card", {}, term)),
        formSection(t("Definition"), el(".form-card", {}, definition)),
        formSection(t("Notes (optional)"), el(".form-card", {}, notes)),
        isEditing ? formSection(null, el(".form-card", {},
          el("button.form-action.danger", { onclick: deleteThisEntry }, icon("delete", 20), t("Delete Term")))) : null,
        errorEl,
      ),
    );
  });
}
