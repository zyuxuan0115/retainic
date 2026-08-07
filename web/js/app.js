//
//  Application boot, tab shell, and navigation coordinator.
//  Retainic Web
//

import { el, clear } from "./dom.js";
import { t, preferredLanguage } from "./i18n.js";
import * as Auth from "./auth.js";
import { authState } from "./auth.js";
import { AuthScreen } from "./screens/auth-screen.js";
import { ListsScreen } from "./screens/lists-screen.js";
import { ListDetailScreen } from "./screens/list-detail-screen.js";
import { GlossariesScreen, glossaryGlyph } from "./screens/glossaries-screen.js";
import { GlossaryDetailScreen } from "./screens/glossary-detail-screen.js";
import { TrashScreen } from "./screens/trash-screen.js";
import { FlashcardScreen } from "./screens/flashcard-screen.js";
import { StatsScreen } from "./screens/stats-screen.js";
import { SettingsScreen } from "./screens/settings-screen.js";
import { AboutScreen } from "./screens/about-screen.js";
import { icon, bookIcon, listsGlyph, chartGlyph, gearGlyph } from "./ui.js";

const root = document.getElementById("app");

// Navigation state. The My Lists and My Glossaries tabs each own a navigation
// stack; the other tabs are single screens.
const state = {
  tab: "lists",
  stacks: {
    lists: [{ name: "lists" }],
    glossaries: [{ name: "glossaries" }],
  },
};

const isStackTab = (tab) => tab in state.stacks;

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
      tabItem("glossaries", glossaryGlyph(), t("My Glossaries")),
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
      onclick: () => {
        state.tab = tab;
        if (isStackTab(tab) && state.stacks[tab].length === 0) state.stacks[tab] = [{ name: tab }];
        renderApp();
      },
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
  const stack = isStackTab(state.tab) ? state.stacks[state.tab] : null;
  const top = stack ? stack[stack.length - 1] : null;
  // Practice is only available while browsing a list's or glossary's contents;
  // the detail screens re-enable it once their rows load.
  if (!(top && top.name === "detail")) setPractice(null);
  if (top && top.name === "practice") {
    FlashcardScreen(content, top.ctx, navPop);
  } else if (state.tab === "lists") {
    if (top.name === "lists") ListsScreen(content, (list) => navPush({ name: "detail", list }));
    else ListDetailScreen(content, top.list, { onBack: navPop, onPracticeChange: setPractice });
  } else if (state.tab === "glossaries") {
    if (top.name === "glossaries") GlossariesScreen(content, (glossary) => navPush({ name: "detail", glossary }));
    else GlossaryDetailScreen(content, top.glossary, { onBack: navPop, onPracticeChange: setPractice });
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

function navPush(screen) { state.stacks[state.tab].push(screen); renderApp(); }
function navPop() { state.stacks[state.tab].pop(); renderApp(); }

// The sidebar "Practice" action is only usable while browsing a list's words or
// a glossary's terms. `currentPractice` holds that deck's practice context (or
// null); `practiceNavEl` is the sidebar button, toggled enabled/disabled to
// match.
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
  // Practice belongs to the tab whose deck is open, so it stacks on top of that
  // tab's detail screen and Back returns there.
  state.tab = currentPractice.kind === "glossary" ? "glossaries" : "lists";
  navPush({ name: "practice", ctx: currentPractice });
}
