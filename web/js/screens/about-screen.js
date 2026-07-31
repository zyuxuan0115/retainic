//
//  About and project links.
//  Retainic Web
//

import { el } from "../dom.js";
import { t } from "../i18n.js";
import { navBar, formSection, icon } from "../ui.js";

const APP_VERSION = "1.0";
const REPO_URL = "https://github.com/zyuxuan0115/retainic";

export function AboutScreen(content) {
  content.appendChild(navBar(t("About"), {}));
  const body = el(".scroll");
  content.appendChild(body);

  body.appendChild(el(".about", {},
    el(".about-hero", {},
      el(".about-logo", {}, icon("menu_book", 56)),
      el("h1", {}, "Retainic"),
      el("p.muted", {}, t("Vocabulary learning with spaced-repetition flashcards.")),
      el(".about-version", {}, `${t("Version")} ${APP_VERSION}`),
    ),
    el(".form", {},
      formSection(t("About"), el(".form-card", {},
        el(".about-text", {}, t("Retainic lets you build vocabulary lists, add words with translations, readings, parts of speech and recorded pronunciation, then practice them with per-aspect spaced repetition. This web app shares the same account and data as the Retainic iOS app.")),
      )),
      formSection(t("Source code"), el(".form-card", {},
        el("a.form-action.link", { href: REPO_URL, target: "_blank", rel: "noopener" },
          icon("code", 20),
          el("span", { style: "flex:1" }, "github.com/zyuxuan0115/retainic"),
          icon("open_in_new", 18),
        ),
      )),
      el("p.caption.center", {}, "© 2026 Retainic"),
    ),
  ));
}
