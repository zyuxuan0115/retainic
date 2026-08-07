//
//  Add and edit glossary entry flow.
//  Retainic Web
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, displayNameIn } from "../i18n.js";
import * as Repo from "../repository.js";
import * as G from "../glossary.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { icon, iconButton, formSection, confirmDialog } from "../ui.js";

export function presentEntrySheet({ glossary, entry, onSaved }) {
  const isEditing = entry != null;

  presentSheet((api) => {
    const term = el("input.field-input", { type: "text", value: entry?.term || "", placeholder: t("Term") });
    const notes = el("textarea.field-input", { rows: 3, placeholder: t("Example sentence or memory hint") }, entry?.notes || "");
    const errorEl = el(".form-footer-error");
    const saveBtn = el("button.icon-btn", { onclick: save, title: t("Save"), "aria-label": t("Save") }, icon("check", 24));

    // A term can mean several things, so the definition section is a list of
    // fields: each one is practised (and scheduled) on its own.
    const savedDefinitions = isEditing ? G.definitionTexts(entry) : [];
    let definitionValues = savedDefinitions.length ? [...savedDefinitions] : [""];
    const definitionsCard = el(".form-card");

    const filledDefinitions = () => definitionValues.map((d) => d.trim()).filter(Boolean);

    function renderDefinitions() {
      clear(definitionsCard);
      definitionValues.forEach((value, index) => {
        const field = el("textarea", { rows: 2, placeholder: t("What it means") }, value);
        field.addEventListener("input", () => { definitionValues[index] = field.value; validate(); });
        definitionsCard.appendChild(el(".definition-row", {},
          field,
          // The last remaining field stays: an entry always has a definition.
          definitionValues.length > 1
            ? iconButton(icon("close", 18), () => {
                definitionValues.splice(index, 1);
                renderDefinitions();
                validate();
              }, { label: t("Remove definition") })
            : null,
        ));
      });
      definitionsCard.appendChild(el("button.form-action", {
        onclick: () => { definitionValues.push(""); renderDefinitions(); validate(); },
      }, icon("add", 20), t("Add definition")));
    }

    // When editing, Save stays disabled until something actually changes.
    function hasChanges() {
      if (!isEditing) return true;
      const definitions = filledDefinitions();
      return term.value.trim() !== (entry.term || "")
        || definitions.length !== savedDefinitions.length
        || definitions.some((d, i) => d !== savedDefinitions[i])
        || notes.value.trim() !== (entry.notes || "");
    }
    function validate() {
      const ok = term.value.trim() && filledDefinitions().length && hasChanges();
      saveBtn.disabled = !ok;
      saveBtn.classList.toggle("disabled", !ok);
    }
    [term, notes].forEach((i) => i.addEventListener("input", validate));
    renderDefinitions();

    async function save() {
      if (saveBtn.disabled) return;
      saveBtn.disabled = true;
      try {
        if (isEditing) {
          const updated = { ...entry, term: term.value.trim(), notes: notes.value.trim() };
          G.setDefinitions(updated, filledDefinitions());
          await Repo.updateEntry(authState.uid, glossary.id, updated);
        } else {
          await Repo.addEntry(authState.uid, glossary.id, G.newEntry({
            term: term.value.trim(),
            definitions: filledDefinitions(),
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
        formSection(t("Definitions"), definitionsCard),
        formSection(t("Notes (optional)"), el(".form-card", {}, notes)),
        isEditing ? formSection(null, el(".form-card", {},
          el("button.form-action.danger", { onclick: deleteThisEntry }, icon("delete", 20), t("Delete Term")))) : null,
        errorEl,
      ),
    );
  });
}
