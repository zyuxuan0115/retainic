//
//  Custom review-algorithm editor and syntax highlighting.
//  Retainic Web
//

import { el, presentSheet } from "../dom.js";
import { t } from "../i18n.js";
import { DEFAULT_ALGORITHM_CODE, compileAlgorithm } from "../algorithm.js";
import { icon } from "../ui.js";

const PY_KEYWORDS = new Set([
  "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
  "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
  "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
  "with", "yield", "match", "case",
]);
const PY_CONSTS = new Set(["True", "False", "None"]);

/** Turns Python source into highlighted HTML. Every character is preserved and
 *  HTML-escaped, so the result lines up exactly under the editing textarea. */
export function highlightPython(src) {
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const span = (cls, s) => `<span class="${cls}">${esc(s)}</span>`;
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === "#") {                                   // comment to end of line
      let j = i; while (j < n && src[j] !== "\n") j++;
      out += span("tok-com", src.slice(i, j)); i = j; continue;
    }
    if ((c === '"' || c === "'") && src.substr(i, 3) === c + c + c) {  // triple string
      const q = c + c + c;
      let j = i + 3; while (j < n && src.substr(j, 3) !== q) j++;
      j = Math.min(n, j + 3);
      out += span("tok-str", src.slice(i, j)); i = j; continue;
    }
    if (c === '"' || c === "'") {                      // single/double string
      let j = i + 1;
      while (j < n && src[j] !== c && src[j] !== "\n") { if (src[j] === "\\") j++; j++; }
      if (j < n && src[j] === c) j++;
      out += span("tok-str", src.slice(i, j)); i = j; continue;
    }
    if (/[0-9]/.test(c)) {                             // number
      let j = i + 1; while (j < n && /[0-9a-fA-FxXoObB._]/.test(src[j])) j++;
      out += span("tok-num", src.slice(i, j)); i = j; continue;
    }
    if (/[A-Za-z_]/.test(c)) {                         // identifier / keyword / call
      let j = i + 1; while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
      const word = src.slice(i, j);
      let k = j; while (k < n && src[k] === " ") k++;
      let cls = null;
      if (PY_KEYWORDS.has(word)) cls = "tok-kw";
      else if (PY_CONSTS.has(word)) cls = "tok-const";
      else if (src[k] === "(") cls = "tok-fn";
      out += cls ? span(cls, word) : esc(word);
      i = j; continue;
    }
    out += esc(c); i++;
  }
  return out;
}

/** A syntax-highlighted code editor: a transparent <textarea> over a colored
 *  <pre>. Returns the wrapper, the textarea (for reading .value), and setValue. */
export function codeEditor(initial) {
  const code = el("code");
  const highlight = el("pre.code-highlight", { "aria-hidden": "true" }, code);
  const textarea = el("textarea.code-editor", {
    spellcheck: "false", autocapitalize: "off", autocomplete: "off", autocorrect: "off",
  });
  const sync = () => {
    // A trailing newline needs an extra blank line so the highlight layer stays
    // as tall as the textarea and the caret doesn't clip.
    code.innerHTML = highlightPython(textarea.value) + (textarea.value.endsWith("\n") ? "\n" : "");
  };
  textarea.addEventListener("input", sync);
  const setValue = (v) => { textarea.value = v; sync(); };
  const wrap = el(".code-editor-wrap", {}, highlight, textarea);
  setValue(initial);
  return { wrap, textarea, setValue };
}

/** A full editor for a list's custom review algorithm (Python). Lets the user
 *  paste code, check it compiles (loads Pyodide), reset to the default, and
 *  save. */
export function presentAlgorithmSheet({ code, onSave }) {
  presentSheet((api) => {
    const initialCode = (code && code.trim()) ? code : DEFAULT_ALGORITHM_CODE;
    const ed = codeEditor(initialCode);
    const editor = ed.textarea;
    const status = el(".form-note.code-status");

    // The top-right check validates the code, then saves and closes — but only
    // if it compiles. A broken snippet shows the error and keeps the sheet open.
    const saveBtn = el("button.icon-btn", {
      onclick: async () => {
        if (saveBtn.disabled) return;
        const codeVal = editor.value;
        // The unchanged default is known-good, so skip the Pyodide round-trip.
        if (codeVal.trim() !== DEFAULT_ALGORITHM_CODE.trim()) {
          setSaveEnabled(false);
          status.classList.remove("ok", "err");
          status.textContent = t("Checking your code…");
          try {
            await compileAlgorithm(codeVal);
          } catch (e) {
            status.textContent = String(e && e.message ? e.message : e);
            status.classList.add("err");
            syncSave();
            return;
          }
        }
        onSave(codeVal);
        api.close();
      },
      title: t("Save"), "aria-label": t("Save"),
    }, icon("check", 24));

    function setSaveEnabled(enabled) {
      saveBtn.disabled = !enabled;
      saveBtn.classList.toggle("disabled", !enabled);
    }
    // The checkmark is available only once the code differs from what was opened.
    function syncSave() { setSaveEnabled(editor.value !== initialCode); }
    editor.addEventListener("input", syncSave);
    syncSave();

    const resetBtn = el("button.btn", {
      onclick: () => { ed.setValue(DEFAULT_ALGORITHM_CODE); status.textContent = ""; status.classList.remove("ok", "err"); syncSave(); },
    }, t("Reset to default"));

    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, el("button.icon-btn", {
          onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
        }, icon("close", 24))),
        el(".sheet-title", {}, t("Edit review algorithm")),
        el(".sheet-side.trailing", {}, saveBtn),
      ),
      el(".scroll", {},
        el(".form", {},
          el(".form-note", {}, t("Your function runs in your browser (Python via Pyodide). It's used only for scheduling this list; your words are never changed by it.")),
          ed.wrap,
          el(".algo-actions", {}, resetBtn),
          status,
        ),
      ),
    );
  });
}
