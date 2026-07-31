//
//  Authentication screen.
//  Retainic Web
//

import { el, clear } from "../dom.js";
import { t, LANGUAGES, autonym, preferredLanguage, setPreferredLanguage } from "../i18n.js";
import * as Auth from "../auth.js";
import { icon, bookIcon, glyph } from "../ui.js";

export function AuthScreen() {
  let mode = "login"; // or "register"
  let error = null;
  let working = false;
  const wrap = el(".auth-wrap");

  function render() {
    clear(wrap);
    const isRegister = mode === "register";
    const username = el("input.field-input", { type: "text", placeholder: t("Username"), autocomplete: "username" });
    const email = el("input.field-input", { type: "email", placeholder: t("Email"), autocomplete: "email" });
    const password = el("input.field-input", { type: "password", placeholder: t("Password"), autocomplete: isRegister ? "new-password" : "current-password" });
    const invite = el("input.field-input", { type: "text", placeholder: t("Invitation code"), autocomplete: "off", autocapitalize: "off", spellcheck: "false" });

    const submit = async () => {
      error = null;
      const em = email.value.trim();
      const emailOK = em.includes("@") && em.includes(".");
      const passOK = password.value.length >= 6;
      const userOK = !isRegister || username.value.trim().length > 0;
      const inviteOK = !isRegister || invite.value.trim().length > 0;
      if (!emailOK || !passOK || !userOK || !inviteOK) return;
      working = true; render();
      try {
        if (isRegister) await Auth.register(em, password.value, username.value.trim(), invite.value.trim());
        else await Auth.signIn(em, password.value);
        // onAuthChange re-renders the app.
      } catch (e) {
        console.error("Auth failed:", e?.code, e?.message, e);
        error = `${Auth.friendlyMessage(e)} (${e?.code || "unknown"})`;
        working = false; render();
      }
    };

    const langSel = el("select.picker", { onchange: (e) => setPreferredLanguage(e.target.value) },
      ...LANGUAGES.map((l) => el("option", { value: l.code, selected: l.code === preferredLanguage() }, autonym(l.code))));

    wrap.appendChild(el(".auth-card", {},
      el(".auth-lang", {}, icon("language", 18), langSel),
      el(".auth-header", {},
        el(".auth-logo", {}, bookIcon(44)),
        el("h1", {}, "Retainic"),
        el("p", {}, t("Sign in to access your vocabulary lists.")),
      ),
      el(".segmented", {},
        segButton(t("Log In"), !isRegister, () => { mode = "login"; error = null; render(); }),
        segButton(t("Register"), isRegister, () => { mode = "register"; error = null; render(); }),
      ),
      el(".auth-fields", {},
        isRegister ? fieldRow("person", username) : null,
        fieldRow("envelope", email),
        fieldRow("lock", password),
        isRegister ? fieldRow("key", invite) : null,
      ),
      error ? el(".form-error", {}, error) : null,
      el("button.btn.primary.large", {
        disabled: working,
        onclick: submit,
      }, working ? t("Loading…") : (isRegister ? t("Create Account") : t("Log In"))),
      isRegister ? el(".caption.center", {}, t("Password must be at least 6 characters.")) : null,
    ));

    [username, email, password, invite].forEach((inp) =>
      inp.addEventListener("keydown", (e) => { if (e.key === "Enter") submit(); }));
  }

  function segButton(label, active, onClick) {
    return el("button.seg" + (active ? ".active" : ""), { onclick: onClick }, label);
  }
  function fieldRow(icon, input) {
    return el(".field-row", {}, el(".field-icon", {}, glyph(icon)), input);
  }

  render();
  return wrap;
}
