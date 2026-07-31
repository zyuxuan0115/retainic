//
//  Account and language settings.
//  Retainic Web
//

import { el, presentSheet, toast } from "../dom.js";
import { t, LANGUAGES, autonym, preferredLanguage, setPreferredLanguage } from "../i18n.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { navBar, labeledRow, pickerRow, formSection, confirmDialog, icon } from "../ui.js";

export function SettingsScreen(content) {
  content.appendChild(navBar(t("Settings"), {}));
  const body = el(".scroll");
  content.appendChild(body);

  const langSel = el("select.picker", { onchange: (e) => setPreferredLanguage(e.target.value) },
    ...LANGUAGES.map((l) => el("option", { value: l.code, selected: l.code === preferredLanguage() }, autonym(l.code))));

  body.appendChild(el(".form", {},
    formSection(t("Account"), el(".form-card", {},
      labeledRow(t("Username"), authState.profile?.username || authState.displayName || "—"),
      labeledRow(t("Email"), authState.profile?.email || authState.email || "—"),
    )),
    formSection(t("Language"), el(".form-card", {}, pickerRow(t("Preferred language"), langSel))),
    formSection(null, el(".form-card", {},
      el("button.form-action", {
        onclick: () => presentChangePasswordSheet(),
      }, icon("lock", 20), t("Change Password")))),
    formSection(null, el(".form-card", {},
      el("button.form-action.danger", {
        onclick: () => confirmDialog({
          message: t("Sign out of Retainic?"), confirmLabel: t("Sign Out"), danger: true,
          onConfirm: () => Auth.signOut(),
        }),
      }, t("Sign Out")))),
  ));
}

/** Sheet to change the account password. The user must enter their current
 *  password correctly (verified by reauthentication) before the new one is set. */
function presentChangePasswordSheet() {
  presentSheet((api) => {
    const current = el("input.field-input", { type: "password", placeholder: t("Current password"), autocomplete: "current-password" });
    const next = el("input.field-input", { type: "password", placeholder: t("New password"), autocomplete: "new-password" });
    const confirm = el("input.field-input", { type: "password", placeholder: t("Confirm new password"), autocomplete: "new-password" });
    const errorEl = el(".form-footer-error");
    let working = false;

    const saveBtn = el("button.icon-btn", { onclick: save, title: t("Save"), "aria-label": t("Save") }, icon("check", 24));

    function validate() {
      const ok = current.value.length > 0 && next.value.length >= 6 && confirm.value === next.value;
      saveBtn.disabled = !ok || working;
      saveBtn.classList.toggle("disabled", saveBtn.disabled);
    }
    [current, next, confirm].forEach((inp) =>
      inp.addEventListener("input", () => { errorEl.textContent = ""; validate(); }));

    async function save() {
      if (saveBtn.disabled) return;
      if (next.value !== confirm.value) { errorEl.textContent = t("The new passwords don't match."); return; }
      working = true; validate();
      api.setDismissible(false);
      try {
        await Auth.changePassword(current.value, next.value);
        api.close();
        toast(t("Password changed."));
      } catch (e) {
        working = false; validate();
        api.setDismissible(true);
        errorEl.textContent = Auth.friendlyMessage(e);
      }
    }

    setTimeout(validate, 0);
    [current, next, confirm].forEach((inp) =>
      inp.addEventListener("keydown", (e) => { if (e.key === "Enter") save(); }));

    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, el("button.icon-btn", {
          onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
        }, icon("close", 24))),
        el(".sheet-title", {}, t("Change Password")),
        el(".sheet-side.trailing", {}, saveBtn),
      ),
      el(".form", {},
        formSection(t("Current password"), el(".form-card", {}, current)),
        formSection(t("New password"), el(".form-card", {}, next),
          el(".form-note", {}, t("Password must be at least 6 characters."))),
        formSection(t("Confirm new password"), el(".form-card", {}, confirm)),
        errorEl,
      ),
    );
  });
}
