//
//  Application boot, tab shell, and navigation coordinator.
//  Retainic Web
//

import { el, clear } from "./dom.js";
import { t, preferredLanguage } from "./i18n.js";
import * as Auth from "./auth.js";
import { authState } from "./auth.js";
import { AuthScreen } from "./screens/auth-screen.js";
import { ListsScreen, TrashScreen } from "./screens/lists-screen.js";
import { ListDetailScreen } from "./screens/list-detail-screen.js";
import { FlashcardScreen } from "./screens/flashcard-screen.js";
import { StatsScreen } from "./screens/stats-screen.js";
import { SettingsScreen } from "./screens/settings-screen.js";
import { AboutScreen } from "./screens/about-screen.js";
import { icon, bookIcon, listsGlyph, chartGlyph, gearGlyph } from "./ui.js";

const root = document.getElementById("app");

// Navigation state for the My Lists tab.
const state = {
  tab: "lists",
  stack: [{ name: "lists" }],
};

Auth.onAuthChange(() => renderApp());
window.addEventListener("languagechange-app", () => renderApp());
document.documentElement.lang = preferredLanguage();

function renderApp() {
  clear(root);
  root.appendChild(authState.isAuthenticated ? Shell() : AuthScreen());
}

function Shell() {
  const content = el(".content");
  const shell = el(".shell", {},
    content,
    el(".tabbar", {},
      el(".tabbar-brand", {}, bookIcon(24), el("span", {}, "Retainic")),
      tabItem("lists", listsGlyph(), t("My Lists")),
      practiceItem(),
      tabItem("trash", icon("delete", 24), t("Trash")),
      tabItem("stats", chartGlyph(), t("Statistics")),
      tabItem("settings", gearGlyph(), t("Settings")),
      tabItem("about", icon("info", 24), t("About")),
    ),
  );
  renderTab(content);
  return shell;

  function tabItem(tab, icon, label) {
    return el(".tab" + (state.tab === tab ? ".active" : ""), {
      title: label,
      onclick: () => { state.tab = tab; if (tab === "lists" && state.stack.length === 0) state.stack = [{ name: "lists" }]; renderApp(); },
    }, el(".tab-icon", {}, icon), el(".tab-label", {}, label));
  }

  function practiceItem() {
    practiceNavEl = el(".tab.action" + (currentPractice ? "" : ".disabled"), {
      onclick: startCurrentPractice,
      title: t("Practice"),
    }, el(".tab-icon", {}, icon("style", 24)), el(".tab-label", {}, t("Practice")));
    return practiceNavEl;
  }
}

function renderTab(content) {
  clear(content);
  const top = state.tab === "lists" ? state.stack[state.stack.length - 1] : null;
  // Practice is only available while browsing a list's words; the detail screen
  // re-enables it once its words load.
  if (!(top && top.name === "detail")) setPractice(null);
  if (state.tab === "lists") {
    if (top.name === "lists") ListsScreen(content, (list) => navPush({ name: "detail", list }));
    else if (top.name === "detail") ListDetailScreen(content, top.list, { onBack: navPop, onPracticeChange: setPractice });
    else if (top.name === "practice") FlashcardScreen(content, top.cards, top.learningLanguage, top.ttsEnabled === true, top.algorithmCode || null, navPop);
  } else if (state.tab === "trash") {
    TrashScreen(content);
  } else if (state.tab === "stats") {
    StatsScreen(content);
  } else if (state.tab === "about") {
    AboutScreen(content);
  } else {
    SettingsScreen(content);
  }
}

function navPush(screen) { state.stack.push(screen); renderApp(); }
function navPop() { state.stack.pop(); renderApp(); }

// The sidebar "Practice" action is only usable while browsing a list's words.
// `currentPractice` holds that list's cards (or null); `practiceNavEl` is the
// sidebar button, toggled enabled/disabled to match.
let currentPractice = null;
let practiceNavEl = null;

function setPractice(ctx) {
  currentPractice = ctx;
  updatePracticeNav();
}
function updatePracticeNav() {
  if (!practiceNavEl) return;
  const enabled = !!currentPractice;
  practiceNavEl.classList.toggle("disabled", !enabled);
  practiceNavEl.setAttribute("aria-disabled", String(!enabled));
}
function startCurrentPractice() {
  if (!currentPractice) return;
  state.tab = "lists";
  navPush({ name: "practice", cards: currentPractice.cards, learningLanguage: currentPractice.learningLanguage, ttsEnabled: currentPractice.ttsEnabled, algorithmCode: currentPractice.algorithmCode });
}
