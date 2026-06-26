//
//  i18n.js
//  Retainic Web
//
//  Port of Language.swift + AppLanguage.swift: the supported languages plus the
//  string-lookup helpers that drive the localized interface.
//

import translations from "./translations.js";

export const LANGUAGES = [
  { code: "en", name: "English" },
  { code: "es", name: "Spanish" },
  { code: "zh", name: "Chinese" },
  { code: "ja", name: "Japanese" },
  { code: "ko", name: "Korean" },
];

const PREFERRED_KEY = "retainic.preferredLanguage";

/** The best supported language for the browser, defaulting to English. */
export function systemDefault() {
  const pref = (navigator.languages && navigator.languages[0]) || navigator.language || "en";
  const code = pref.toLowerCase().split("-")[0];
  return LANGUAGES.some((l) => l.code === code) ? code : "en";
}

let _preferred = localStorage.getItem(PREFERRED_KEY) || systemDefault();

export function preferredLanguage() {
  return _preferred;
}

export function setPreferredLanguage(code) {
  _preferred = code;
  localStorage.setItem(PREFERRED_KEY, code);
  document.documentElement.lang = code;
  window.dispatchEvent(new CustomEvent("languagechange-app"));
}

/**
 * Look up a UI string in the preferred (or given) language, falling back to
 * English and then to the key itself. Mirrors String.localized(_:) on iOS.
 */
export function t(key, code = _preferred) {
  const entry = translations[key];
  if (!entry) return key;
  return entry[code] ?? entry.en ?? key;
}

/** Like t(), but substitutes a single integer into a "%lld" format string. */
export function tn(key, n, code = _preferred) {
  return t(key, code).replace("%lld", String(n));
}

/** Substitutes positional "%lld" / "%@" placeholders, in order, with args. */
export function tf(key, ...args) {
  let i = 0;
  return t(key).replace(/%lld|%@/g, () => String(args[i++] ?? ""));
}

const LOCALE_ID = { zh: "zh-Hans" };
function localeId(code) {
  return LOCALE_ID[code] || code;
}

/** A language's name written in the given UI language (e.g. "ja" → "英語"). */
export function displayNameIn(code, uiCode = _preferred) {
  try {
    const dn = new Intl.DisplayNames([localeId(uiCode)], { type: "language" });
    const name = dn.of(code);
    if (name) return name.charAt(0).toUpperCase() + name.slice(1);
  } catch {}
  return LANGUAGES.find((l) => l.code === code)?.name ?? code;
}

/** A language's name written in itself (its autonym), e.g. "Español", "日本語". */
export function autonym(code) {
  return displayNameIn(code, code);
}

export function languageName(code) {
  return LANGUAGES.find((l) => l.code === code)?.name ?? code;
}
