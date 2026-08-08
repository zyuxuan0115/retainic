import assert from "node:assert/strict";
import { test } from "node:test";

import translations from "../js/translations.js";

test("every translation has an English fallback", () => {
  assert.equal(Object.keys(translations).length, 241);
  for (const [key, entry] of Object.entries(translations)) {
    assert.equal(typeof entry.en, "string", key);
  }
});

test("translation lookup keeps localized and key fallbacks", async () => {
  const defineGlobal = (name, value) => Object.defineProperty(globalThis, name, {
    configurable: true,
    value,
    writable: true,
  });
  defineGlobal("navigator", { languages: ["en"], language: "en" });
  defineGlobal("localStorage", {
    getItem: () => null,
    setItem: () => {},
  });
  defineGlobal("document", { documentElement: { lang: "en" } });
  defineGlobal("window", { dispatchEvent: () => {} });
  defineGlobal("CustomEvent", class CustomEvent {});

  const { setPreferredLanguage, t, tn } = await import("../js/i18n.js");
  assert.equal(t("Change Password", "es"), "Cambiar contraseña");
  assert.equal(t("missing translation", "ja"), "missing translation");
  assert.equal(t("Change Password", "unsupported"), "Change Password");

  setPreferredLanguage("en");
  assert.equal(tn("%lld words", 3), "3 words");
});
