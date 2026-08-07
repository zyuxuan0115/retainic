//
//  Glossary overview and creation.
//  Retainic Web
//
//  A glossary is a single-language collection of terms and definitions, kept
//  entirely separate from vocabulary lists: its own dashboard, its own
//  documents (see repository.js), its own practice deck.
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, tn, displayNameIn } from "../i18n.js";
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

function presentNewGlossarySheet(onCreated) {
  presentSheet((api) => {
    // A glossary is monolingual: terms and definitions are both written in this
    // one language, so there is no translation language to pick.
    let language = "";
    const name = el("input.field-input", { type: "text", placeholder: t("e.g. Legal terms") });
    const langSel = languageSelect(language, t("Select…"), (v) => { language = v; validate(); });
    const footer = el(".form-footer-error");
    name.addEventListener("input", validate);

    const createBtn = el("button.icon-btn", { onclick: submit, title: t("Create"), "aria-label": t("Create") }, icon("check", 24));
    const cancelBtn = el("button.icon-btn", {
      onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
    }, icon("close", 24));

    function validate() {
      const ok = Boolean(name.value.trim() && language);
      createBtn.disabled = !ok;
      createBtn.classList.toggle("disabled", !ok);
    }

    async function submit() {
      if (createBtn.disabled) return;
      try {
        await Repo.createGlossary(authState.uid, name.value.trim(), language);
        api.close();
        onCreated();
      } catch (e) { toast(Auth.friendlyMessage(e)); }
    }

    setTimeout(validate, 0);
    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, cancelBtn),
        el(".sheet-title", {}, t("New Glossary")),
        el(".sheet-side.trailing", {}, createBtn),
      ),
      el(".form", {},
        formSection(t("Glossary name"), el(".form-card", {}, name)),
        formSection(t("Language"),
          el(".form-card", {}, pickerRow(t("Terms are in"), langSel)),
          el(".form-note", {}, t("Terms and definitions are both written in this language.")),
          footer),
      ),
    );
  });
}
