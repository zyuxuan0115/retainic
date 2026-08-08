//
//  Shared DOM controls, feedback, audio controls, and icon primitives.
//  Retainic Web
//

import { el, clear, presentSheet, toast } from "./dom.js";
import { t, LANGUAGES, displayNameIn } from "./i18n.js";
import * as Auth from "./auth.js";
import { playback, ttsKey } from "./audio.js";

export function navBar(title, { leading = null, trailing = null } = {}) {
  return el(".navbar", {},
    el(".navbar-side.leading", {}, leading),
    el(".navbar-title", {}, title),
    el(".navbar-side.trailing", {}, trailing),
  );
}

export function iconButton(symbol, onClick, { label = "", danger = false, disabled = false } = {}) {
  return el("button.icon-btn" + (danger ? ".danger" : "") + (disabled ? ".disabled" : ""),
    { onclick: onClick, title: label, "aria-label": label, disabled }, symbol);
}

export function textButton(label, onClick, { kind = "plain" } = {}) {
  return el(`button.txt-btn.${kind}`, { onclick: onClick }, label);
}

export function spinner(label) {
  return el(".center-state", {}, el(".spinner"), label ? el("p", {}, label) : null);
}

export function emptyState(icon, title, desc, action = null) {
  return el(".center-state", {},
    el(".empty-icon", {}, icon),
    el("h2", {}, title),
    el("p", {}, desc),
    action,
  );
}

export function pronunciationButton(word, list, large = false) {
  if (word.audioPath) return playbackButton(word.audioPath, large);
  if (list.ttsEnabled === true && word.term) {
    return audioButton(ttsKey(word.term), large, (e) => {
      e.stopPropagation();
      playback.speakToggle(word.term, list.learningLanguage || "");
    });
  }
  return null;
}

export function playbackButton(path, large = false) {
  return audioButton(path, large, (e) => { e.stopPropagation(); playback.toggle(path); });
}

/** Shared audio button: shows a speaker/stop glyph tracking `key`'s play state
 *  and runs `onClick` when tapped. Used for both recordings and TTS. */
function audioButton(key, large, onClick) {
  const btn = el("button.audio-btn" + (large ? ".large" : ""), {}, speakerGlyph());
  const update = (playingPath) => {
    const playing = playingPath === key;
    clear(btn);
    btn.appendChild(playing ? stopGlyph() : speakerGlyph());
    if (large) btn.appendChild(document.createTextNode(" " + (playing ? t("Stop") : t("Play pronunciation"))));
  };
  btn.addEventListener("click", onClick);
  playback.subscribe(update);
  update(playback.playingPath);
  // Clean up subscription when removed (best-effort)
  return btn;
}

export function labeledRow(label, value) {
  return el(".labeled-row", {}, el("span.lr-label", {}, label), el("span.lr-value", {}, value));
}
export function pickerRow(label, select) {
  return el(".picker-row", {}, el("span", {}, label), select);
}
/** A language dropdown listing every supported language, with `placeholder` as
 *  the empty choice. Used by the new-list and new-glossary sheets. */
export function languageSelect(value, placeholder, onChange) {
  return el("select.picker", { onchange: (e) => onChange(e.target.value) },
    el("option", { value: "" }, placeholder),
    ...LANGUAGES.map((l) => el("option", { value: l.code, selected: l.code === value }, displayNameIn(l.code))),
  );
}
export function formSection(title, ...cards) {
  return el(".form-section", {}, title ? el(".section-title", {}, title) : null, ...cards.filter(Boolean));
}
export function sheetHeader(title, api, confirmBtn, cancelLabel) {
  return el(".sheet-header", {},
    el(".sheet-side", {}, cancelLabel === null ? null : textButton(cancelLabel || t("Cancel"), () => api.close())),
    el(".sheet-title", {}, title),
    el(".sheet-side.trailing", {}, confirmBtn),
  );
}
export function errorState(e) {
  return emptyState(icon("error", 46), t("Something went wrong"), Auth.friendlyMessage(e));
}

/** An in-app confirmation panel. By default the confirm button closes the panel
 *  and runs `onConfirm`. If `workingLabel` is given, the action is treated as a
 *  non-interruptible async task: the confirm button shows `workingLabel` and
 *  greys out, Cancel is disabled, a click outside does nothing, and the panel
 *  closes only once `onConfirm` resolves (re-enabling on failure). */
export function confirmDialog({ message, confirmLabel, workingLabel, danger = false, onConfirm }) {
  presentSheet((api) => {
    const cancelBtn = el("button.btn.subtle", { onclick: () => api.close() }, t("Cancel"));
    const confirmBtn = el("button.btn." + (danger ? "destructive" : "primary"), {}, confirmLabel || t("OK"));

    if (workingLabel) {
      api.setDismissible(false); // clicking outside the panel does nothing
      confirmBtn.addEventListener("click", async () => {
        if (confirmBtn.disabled) return;
        cancelBtn.disabled = true;
        confirmBtn.disabled = true;
        confirmBtn.textContent = workingLabel;
        try {
          await onConfirm();
          api.close();
        } catch (e) {
          cancelBtn.disabled = false;
          confirmBtn.disabled = false;
          confirmBtn.textContent = confirmLabel || t("OK");
          toast(Auth.friendlyMessage(e));
        }
      });
    } else {
      confirmBtn.addEventListener("click", () => { api.close(); onConfirm(); });
    }

    return el(".confirm", {},
      el(".confirm-msg", {}, message),
      el(".confirm-actions", {}, cancelBtn, confirmBtn),
    );
  }, { variant: "alert" });
}

// MARK: - Icons (Google Material Symbols)

/** A Material Symbols glyph. `name` is the symbol's ligature name; `size` (px)
 *  is optional and otherwise inherits from the context. */
export function icon(name, size) {
  const s = el("span.msym", {}, name);
  if (size) s.style.fontSize = size + "px";
  return s;
}
/** The turning progress glyph shown while a write runs. */
export function spinningIcon(size = 24) {
  const s = icon("progress_activity", size);
  s.classList.add("spinning");
  return s;
}

/** Swaps a button's glyph for the turning progress one while an import writes,
 *  and back to `symbol` (a fresh glyph) when it's over. */
export function setButtonBusy(button, busy, symbol = null) {
  clear(button);
  button.classList.toggle("busy", busy);
  button.appendChild(busy ? spinningIcon(24) : symbol);
}

export function bookIcon(size = 24) { return icon("menu_book", size); }
export function glyph(name) {
  const map = { person: "person", envelope: "mail", lock: "lock", key: "key" };
  return icon(map[name] || "circle", 20);
}
export function listsGlyph() { return icon("view_list", 24); }
export function chartGlyph(size = 24) { return icon("bar_chart", size); }
export function gearGlyph() { return icon("settings", 24); }
export function rectStackGlyph() { return icon("stacks", 24); }
export function bookClosedGlyph() { return icon("menu_book", 24); }
export function speakerGlyph() { return icon("volume_up", 18); }
export function stopGlyph() { return icon("stop", 18); }
