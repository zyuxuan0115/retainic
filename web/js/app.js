//
//  app.js
//  Retainic Web
//
//  The whole interface: auth gate, tab shell, and every screen — a faithful
//  port of the SwiftUI views (ContentView, MainTabView, AuthView,
//  VocabListsView, ListDetailView, AddWordView, FlashcardView, StatsView,
//  SettingsView).
//

import { el, clear, svgEl, presentSheet, toast } from "./dom.js";
import * as i18n from "./i18n.js";
import { t, tn, tf, LANGUAGES, autonym, displayNameIn, preferredLanguage, setPreferredLanguage } from "./i18n.js";
import * as Repo from "./repository.js";
import * as M from "./models.js";
import * as Auth from "./auth.js";
import { authState } from "./auth.js";
import { playback, PronunciationRecorder } from "./audio.js";

const root = document.getElementById("app");

// Navigation state for the "My Lists" tab (a simple screen stack).
const state = {
  tab: "lists",
  stack: [{ name: "lists" }],
};

const APP_VERSION = "1.0";
const REPO_URL = "https://github.com/zyuxuan0115/retainic";

// MARK: - Boot

Auth.onAuthChange(() => renderApp());
window.addEventListener("languagechange-app", () => renderApp());
document.documentElement.lang = preferredLanguage();

function renderApp() {
  clear(root);
  if (!authState.isAuthenticated) {
    root.appendChild(AuthScreen());
  } else {
    root.appendChild(Shell());
  }
}

// MARK: - Shared building blocks

function navBar(title, { leading = null, trailing = null } = {}) {
  return el(".navbar", {},
    el(".navbar-side.leading", {}, leading),
    el(".navbar-title", {}, title),
    el(".navbar-side.trailing", {}, trailing),
  );
}

function iconButton(symbol, onClick, { label = "", danger = false, disabled = false } = {}) {
  return el("button.icon-btn" + (danger ? ".danger" : "") + (disabled ? ".disabled" : ""),
    { onclick: onClick, title: label, "aria-label": label, disabled }, symbol);
}

function textButton(label, onClick, { kind = "plain" } = {}) {
  return el(`button.txt-btn.${kind}`, { onclick: onClick }, label);
}

function spinner(label) {
  return el(".center-state", {}, el(".spinner"), label ? el("p", {}, label) : null);
}

function emptyState(icon, title, desc, action = null) {
  return el(".center-state", {},
    el(".empty-icon", {}, icon),
    el("h2", {}, title),
    el("p", {}, desc),
    action,
  );
}

// MARK: - Auth

function AuthScreen() {
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

// MARK: - Shell (tab bar)

function Shell() {
  const content = el(".content");
  const shell = el(".shell", {},
    content,
    el(".tabbar", {},
      el(".tabbar-brand", {}, bookIcon(24), el("span", {}, "Retainic")),
      tabItem("lists", listsGlyph(), t("My Lists")),
      practiceItem(),
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
    if (top.name === "lists") ListsScreen(content);
    else if (top.name === "detail") ListDetailScreen(content, top.list);
    else if (top.name === "practice") FlashcardScreen(content, top.cards, top.learningLanguage);
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
  navPush({ name: "practice", cards: currentPractice.cards, learningLanguage: currentPractice.learningLanguage });
}

// MARK: - Lists screen

async function ListsScreen(content) {
  content.appendChild(navBar(t("My Lists"), {
    trailing: iconButton(icon("add", 24), () => presentNewListSheet(reload), { label: t("New List") }),
  }));
  const body = el(".scroll");
  content.appendChild(body);
  body.appendChild(spinner(t("Loading…")));

  async function reload() {
    let lists = [];
    try { lists = await Repo.fetchLists(authState.uid); }
    catch (e) { clear(body); body.appendChild(errorState(e)); return; }
    clear(body);
    if (lists.length === 0) {
      body.appendChild(emptyState(rectStackGlyph(), t("No Lists Yet"),
        t("Create your first vocabulary list to start adding words."),
        el("button.btn.primary", { onclick: () => presentNewListSheet(reload) }, t("Create a List"))));
      return;
    }
    const listEl = el(".list");
    for (const list of lists) {
      listEl.appendChild(el(".row.tappable", { onclick: () => navPush({ name: "detail", list }) },
        el(".row-lead", {}, rectStackGlyph()),
        el(".row-main", {},
          el(".row-title", {}, list.name),
          el(".row-sub", {}, tn("%lld words", list.wordCount ?? 0)),
        ),
        iconButton(icon("delete", 22), (e) => {
          e.stopPropagation();
          confirmDialog({
            message: `${t("Delete")} “${list.name}”?`, confirmLabel: t("Delete"), danger: true,
            onConfirm: async () => {
              try { await Repo.deleteList(authState.uid, list.id); reload(); }
              catch (err) { toast(Auth.friendlyMessage(err)); }
            },
          });
        }, { label: t("Delete"), danger: true }),
        el(".row-chevron", {}, icon("chevron_right", 22)),
      ));
    }
    body.appendChild(listEl);
  }
  reload();
}

function presentNewListSheet(onCreated) {
  presentSheet((api) => {
    let learning = "";
    let original = preferredLanguage();
    const name = el("input.field-input", { type: "text", placeholder: t("e.g. Kitchen vocabulary") });
    const learnSel = languageSelect(learning, t("Select…"), (v) => { learning = v; validate(); });
    const origSel = languageSelect(original, t("Select…"), (v) => { original = v; validate(); });
    const footer = el(".form-footer-error");
    const createBtn = el("button.txt-btn.bold", { onclick: create }, t("Create"));

    function validate() {
      const same = learning !== "" && learning === original;
      footer.textContent = same ? t("The two languages must be different.") : "";
      const ok = name.value.trim() && learning && original && !same;
      createBtn.disabled = !ok;
      createBtn.classList.toggle("disabled", !ok);
    }
    name.addEventListener("input", validate);

    async function create() {
      if (createBtn.disabled) return;
      try {
        await Repo.createList(authState.uid, name.value.trim(), learning, original);
        api.close();
        onCreated();
      } catch (e) { toast(Auth.friendlyMessage(e)); }
    }

    setTimeout(validate, 0);
    return el(".sheet-content", {},
      sheetHeader(t("New List"), api, createBtn),
      el(".form", {},
        formSection(t("List name"), el(".form-card", {}, name)),
        formSection(t("Languages"),
          el(".form-card", {},
            pickerRow(t("I'm learning"), learnSel),
            pickerRow(t("Translated into"), origSel),
          ), footer),
      ),
    );
  });
}

function languageSelect(value, placeholder, onChange) {
  const sel = el("select.picker", { onchange: (e) => onChange(e.target.value) },
    el("option", { value: "" }, placeholder),
    ...LANGUAGES.map((l) => el("option", { value: l.code, selected: l.code === value }, displayNameIn(l.code))),
  );
  return sel;
}

// MARK: - List detail screen

async function ListDetailScreen(content, list) {
  let words = [];
  let selecting = false;
  let selection = new Set();
  let searchText = "";
  let filter = "all"; // all | remembered | unremembered
  let listName = list.name;

  const header = el(".navbar-host");
  const body = el(".scroll");
  content.appendChild(header);
  content.appendChild(body);

  body.appendChild(spinner(t("Loading…")));
  try { words = await Repo.fetchWords(authState.uid, list.id); }
  catch (e) { clear(body); body.appendChild(errorState(e)); return; }
  renderAll();

  // Keep the sidebar Practice action in sync with this list's words.
  function syncPractice() {
    setPractice(words.length
      ? { cards: words.map((w) => ({ word: w, listId: list.id })), learningLanguage: list.learningLanguage || "" }
      : null);
  }

  function filteredWords() {
    let r = words;
    if (filter === "remembered") r = r.filter(M.isRemembered);
    else if (filter === "unremembered") r = r.filter((w) => !M.isRemembered(w));
    const q = searchText.trim().toLowerCase();
    if (q) r = r.filter((w) => w.term.toLowerCase().includes(q) || w.translation.toLowerCase().includes(q));
    return r;
  }

  function renderAll() {
    syncPractice();
    // Nav bar
    clear(header);
    const title = selecting
      ? (selection.size === 0 ? t("Select Words") : tn("%lld Selected", selection.size))
      : listName;
    let trailing;
    if (selecting) {
      const can = selection.size > 0;
      trailing = el(".navbar-actions", {},
        iconButton(icon("drive_file_move", 22), beginMove, { label: t("Move"), disabled: !can }),
        iconButton(icon("delete", 22), deleteSelected, { label: t("Delete"), danger: true, disabled: !can }),
        iconButton(icon("check", 22), endSelection, { label: t("Done") }),
      );
    } else {
      trailing = el(".navbar-actions", {},
        iconButton(icon("settings", 22), openListSettings, { label: t("Settings") }),
        iconButton(icon("add", 24), openAdd, { label: t("Add Word") }),
        words.length ? iconButton(icon("checklist", 22), beginSelection, { label: t("Select") }) : null,
      );
    }
    header.appendChild(navBar(title, {
      leading: selecting ? null : iconButton(icon("arrow_back", 22), () => navPop(), { label: "Back" }),
      trailing,
    }));

    // Body
    clear(body);
    if (words.length === 0) {
      body.appendChild(emptyState(bookClosedGlyph(), t("No Words Yet"),
        tf("Add the words you're learning to “%@”.", listName),
        el("button.btn.primary", { onclick: openAdd }, t("Add Your First Word"))));
      return;
    }
    const search = el("input.search", { type: "search", placeholder: t("Search words"), value: searchText });
    search.addEventListener("input", () => { searchText = search.value; renderRows(); });
    body.appendChild(el(".search-wrap", {}, search));
    const rowsHost = el(".list", { id: "rows-host" });
    body.appendChild(rowsHost);
    renderRows();

    function renderRows() {
      const host = body.querySelector("#rows-host");
      clear(host);
      for (const w of filteredWords()) host.appendChild(wordRow(w));
    }
  }

  function wordRow(w) {
    const checked = selection.has(w.id);
    const posChips = M.partOfSpeechValues(w).map((p) =>
      el(".chip", {}, M.posLabel(p, preferredLanguage())));
    const audioBtn = w.audioPath ? playbackButton(w.audioPath) : null;
    const row = el(".row.word-row" + (selecting && checked ? ".selected" : ""), {
      onclick: () => {
        if (selecting) { toggleSelect(w.id); }
        else openEdit(w);
      },
    },
      selecting ? el(".select-dot" + (checked ? ".on" : ""), {}, checked ? icon("check", 16) : null) : null,
      el(".row-main", {},
        el(".word-top", {},
          el("span.word-term", {}, w.term),
          M.reading(w) ? el("span.word-reading", {}, M.reading(w)) : null,
          ...posChips,
        ),
        el(".row-sub", {}, w.translation),
      ),
      audioBtn,
      !selecting ? el(".row-chevron", {}, icon("chevron_right", 22)) : null,
    );
    return row;
  }


  // Selection
  function beginSelection() { selecting = true; selection = new Set(); renderAll(); }
  function endSelection() { selecting = false; selection = new Set(); renderAll(); }
  function toggleSelect(id) {
    if (selection.has(id)) selection.delete(id); else selection.add(id);
    renderAll();
  }

  function deleteSelected() {
    const ids = new Set(selection);
    if (ids.size === 0) return;
    const message = ids.size === 1 ? t("Delete this word?") : tn("Delete %lld words?", ids.size);
    confirmDialog({
      message, confirmLabel: t("Delete"), danger: true,
      onConfirm: async () => {
        try {
          for (const id of ids) await Repo.deleteWord(authState.uid, list.id, id);
          words = words.filter((w) => !ids.has(w.id));
        } catch (e) { toast(Auth.friendlyMessage(e)); }
        endSelection();
      },
    });
  }

  async function beginMove() {
    let lists = [];
    try { lists = await Repo.fetchLists(authState.uid); } catch (e) { toast(Auth.friendlyMessage(e)); return; }
    const targets = lists.filter((o) => o.id !== list.id
      && o.learningLanguage === list.learningLanguage
      && o.originalLanguage === list.originalLanguage);
    presentMoveSheet(targets, selection.size, async (dest) => {
      const ids = new Set(selection);
      try {
        for (const w of words.filter((x) => ids.has(x.id)))
          await Repo.moveWord(authState.uid, list.id, dest.id, w);
        words = words.filter((w) => !ids.has(w.id));
      } catch (e) { toast(Auth.friendlyMessage(e)); }
      endSelection();
    });
  }

  // Add / edit
  function openAdd() {
    presentWordSheet({ list, word: null, onSaved: reload });
  }
  function openEdit(w) {
    presentWordSheet({ list, word: w, onSaved: reload });
  }
  async function reload() {
    try { words = await Repo.fetchWords(authState.uid, list.id); } catch (e) { toast(Auth.friendlyMessage(e)); }
    renderAll();
  }

  function openListSettings() {
    presentListSettingsSheet({
      name: listName,
      filter,
      onFilter: (f) => { filter = f; renderAll(); },
      onRename: async (newName) => {
        const trimmed = newName.trim();
        if (!trimmed) return;
        listName = trimmed;
        try { await Repo.renameList(authState.uid, list.id, trimmed); } catch (e) { toast(Auth.friendlyMessage(e)); }
        renderAll();
      },
      onReset: async () => {
        try {
          for (const w of words) { M.resetMemory(w); await Repo.updateWord(authState.uid, list.id, w); }
        } catch (e) { toast(Auth.friendlyMessage(e)); }
        renderAll();
      },
    });
  }

}

function presentMoveSheet(targets, count, onSelect) {
  presentSheet((api) => {
    let bodyContent;
    if (targets.length === 0) {
      bodyContent = emptyState(rectStackGlyph(), t("No Compatible Lists"),
        t("You need another list with the same learning and native language to move these words."));
    } else {
      bodyContent = el(".list", {}, ...targets.map((l) =>
        el(".row.tappable", { onclick: () => { onSelect(l); api.close(); } },
          el(".row-lead", {}, rectStackGlyph()),
          el(".row-main", {}, el(".row-title", {}, l.name), el(".row-sub", {}, tn("%lld words", l.wordCount ?? 0))),
        )));
    }
    return el(".sheet-content", {},
      sheetHeader(tn("Move %lld Words", count), api, null),
      el(".scroll", {}, bodyContent),
    );
  });
}

function presentListSettingsSheet({ name, filter, onFilter, onRename, onReset }) {
  presentSheet((api) => {
    const nameInput = el("input.field-input", { type: "text", value: name });
    const filterSel = el("select.picker", { onchange: (e) => onFilter(e.target.value) },
      el("option", { value: "all", selected: filter === "all" }, t("Show all")),
      el("option", { value: "remembered", selected: filter === "remembered" }, t("Show remembered only")),
      el("option", { value: "unremembered", selected: filter === "unremembered" }, t("Show unremembered only")),
    );
    const saveBtn = el("button.txt-btn.bold", { onclick: () => { onRename(nameInput.value); api.close(); } }, t("Save"));
    return el(".sheet-content", {},
      sheetHeader(t("List Settings"), api, saveBtn, t("Cancel")),
      el(".form", {},
        formSection(t("List name"), el(".form-card", {}, nameInput)),
        formSection(t("Show words"), el(".form-card", {}, pickerRow(t("Show words"), filterSel))),
        formSection(null,
          el(".form-card", {},
            el("button.form-action.danger", {
              onclick: () => confirmDialog({
                message: t("Mark all words as not remembered?"),
                confirmLabel: t("Mark All as Not Remembered"), danger: true,
                onConfirm: () => { onReset(); api.close(); },
              }),
            }, icon("replay", 20), t("Mark all as not remembered")),
          ),
          el(".form-note", {}, t("Every word in this list will show up again in practice for all methods."))),
      ),
    );
  });
}

// MARK: - Add / edit word sheet

function presentWordSheet({ list, word, onSaved }) {
  const isEditing = word != null;
  const learning = list.learningLanguage || "";
  const original = list.originalLanguage || "";
  const isJa = learning === "ja";
  const isZh = learning === "zh";

  presentSheet((api) => {
    const recorder = new PronunciationRecorder();
    const selectedPOS = new Set(word ? M.partOfSpeechValues(word) : []);

    const term = el("input.field-input", { type: "text", value: word?.term || "", placeholder: t("Word you're learning") });
    const hiragana = el("input.field-input", { type: "text", value: word?.hiragana || "", placeholder: t("ひらがな reading") });
    const pinyin = el("input.field-input", { type: "text", value: word?.pinyin || "", placeholder: t("pīnyīn reading") });
    const translation = el("input.field-input", { type: "text", value: word?.translation || "", placeholder: t("Translation") });
    const notes = el("textarea.field-input", { rows: 3, placeholder: t("Example sentence or memory hint") }, word?.notes || "");
    const errorEl = el(".form-footer-error");
    const pinyinFooter = el(".form-note");
    const saveBtn = el("button.icon-btn", { onclick: save, title: t("Save"), "aria-label": t("Save") }, icon("check", 24));

    function validate() {
      const ok = term.value.trim() && translation.value.trim() && (!isZh || pinyin.value.trim());
      saveBtn.disabled = !ok;
      saveBtn.classList.toggle("disabled", !ok);
      if (isZh) pinyinFooter.innerHTML = pinyin.value.trim() ? "" : `<span class="danger-text">${t("Pinyin is required for Chinese words.")}</span>`;
    }
    [term, translation, pinyin].forEach((i) => i.addEventListener("input", validate));

    // Pronunciation section
    const pronHost = el(".form-card");
    recorder.onChange = renderPron;
    recorder.configure(word?.audioPath);
    function renderPron() {
      clear(pronHost);
      pronHost.appendChild(el("button.form-action", { onclick: () => recorder.toggleRecording() },
        icon(recorder.isRecording ? "stop" : "mic", 20),
        recorder.isRecording ? t("Stop Recording") : (recorder.hasAudio ? t("Re-record") : t("Record"))));
      if (recorder.hasAudio && !recorder.isRecording) {
        pronHost.appendChild(el("button.form-action", { onclick: () => recorder.isPlaying ? recorder.stopPlayback() : recorder.play() },
          icon(recorder.isPlaying ? "stop" : "play_arrow", 20), recorder.isPlaying ? t("Stop") : t("Play")));
        pronHost.appendChild(el("button.form-action.danger", { onclick: () => recorder.clear() }, icon("delete", 20), t("Delete Recording")));
      }
      const note = recorder.permissionDenied ? t("Microphone access is off. Enable it in Settings to record.")
        : recorder.recordingWasEmpty ? t("No audio was captured. On the Simulator, enable I/O ▸ Audio Input; otherwise try recording on a real device.")
        : "";
      pronNote.innerHTML = note ? `<span class="danger-text">${note}</span>` : "";
    }
    const pronNote = el(".form-note");

    // POS section
    const posHost = el(".form-card");
    function renderPOS() {
      clear(posHost);
      for (const p of M.PARTS_OF_SPEECH) {
        const on = selectedPOS.has(p);
        posHost.appendChild(el(".check-row", {
          onclick: () => { on ? selectedPOS.delete(p) : selectedPOS.add(p); renderPOS(); },
        }, el("span", {}, M.posLabel(p, preferredLanguage())), el("span.check", {}, on ? icon("check", 18) : null)));
      }
    }
    renderPOS();
    renderPron();

    async function save() {
      if (saveBtn.disabled) return;
      const posList = M.PARTS_OF_SPEECH.filter((p) => selectedPOS.has(p));
      const audioBlob = recorder.recordedBlob;
      const removeAudio = isEditing && word.audioPath != null && !recorder.hasAudio;
      saveBtn.disabled = true;
      try {
        if (isEditing) {
          const w = { ...word };
          w.term = term.value.trim();
          w.translation = translation.value.trim();
          w.notes = notes.value.trim();
          w.partsOfSpeech = posList;
          w.partOfSpeech = null;
          w.hiragana = hiragana.value.trim() || null;
          w.pinyin = pinyin.value.trim() || null;
          await Repo.updateWord(authState.uid, list.id, w, { audioBlob, removeAudio });
        } else {
          const w = M.newWord({
            term: term.value.trim(),
            translation: translation.value.trim(),
            notes: notes.value.trim(),
            partsOfSpeech: posList,
            hiragana: hiragana.value.trim() || null,
            pinyin: pinyin.value.trim() || null,
          });
          await Repo.addWord(authState.uid, list.id, w, audioBlob);
        }
        recorder.stopPlayback();
        api.close();
        onSaved();
      } catch (e) {
        errorEl.textContent = Auth.friendlyMessage(e);
        saveBtn.disabled = false;
      }
    }

    setTimeout(validate, 0);
    const learnTitle = displayNameIn(learning) || t("Word");
    const origTitle = displayNameIn(original) || t("Translation");

    return el(".sheet-content", {},
      sheetHeader(isEditing ? t("Edit Word") : t("New Word"), api, saveBtn, isEditing ? null : t("Cancel")),
      el(".form", {},
        formSection(learnTitle, el(".form-card", {}, term)),
        isJa ? formSection(t("Hiragana (optional)"), el(".form-card", {}, hiragana)) : null,
        isZh ? formSection(t("Pinyin (required)"), el(".form-card", {}, pinyin), pinyinFooter) : null,
        formSection(origTitle, el(".form-card", {}, translation)),
        formSection(t("Part of speech"), posHost, el(".form-note", {}, t("Select all that apply."))),
        formSection(t("Pronunciation (optional)"), pronHost, pronNote),
        formSection(t("Notes (optional)"), el(".form-card", {}, notes)),
        errorEl,
      ),
    );
  });
}

// MARK: - Flashcard screen

const FRONT_MODES = [
  { id: "term", labelKey: "Word", aspect: "spelling" },
  { id: "translation", labelKey: "Translation", aspect: "translation" },
  { id: "pronunciation", labelKey: "Audio", aspect: "pronunciation" },
];

function FlashcardScreen(content, cards, learningLanguage) {
  const header = el(".navbar-host");
  const body = el(".scroll");
  content.appendChild(header);
  content.appendChild(body);

  let session = [];   // [{ card, mode }]
  let index = 0;
  let isFlipped = false;
  let selectedModes = new Set(["term"]);
  let correctCount = 0;
  let totalCards = 0;
  let dueOnly = true;
  let finished = false;

  function includes(card, modeId) {
    if (modeId === "pronunciation" && card.word.audioPath == null) return false;
    if (dueOnly) {
      if (modeId === "translation") return M.isTranslationDue(card.word);
      if (modeId === "term") return M.isWordDue(card.word);
      return M.isPronunciationDue(card.word);
    }
    return card.word.remember_final !== true;
  }
  function deck() {
    if (selectedModes.size === 0) return [];
    const items = [];
    for (const mode of selectedModes)
      for (const card of cards) if (includes(card, mode)) items.push({ card, mode });
    // shuffle
    for (let i = items.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [items[i], items[j]] = [items[j], items[i]]; }
    return items;
  }
  function dueCount() {
    let sum = 0;
    for (const mode of selectedModes) sum += cards.filter((c) => includes(c, mode)).length;
    return sum;
  }

  function renderHeader() {
    clear(header);
    header.appendChild(navBar(t("Practice"), {
      leading: iconButton(icon("arrow_back", 22), () => { playback.stop(); navPop(); }, { label: "Back" }),
      trailing: (session.length && !finished) ? textButton(t("End"), () => { finished = true; render(); }) : null,
    }));
  }

  function render() {
    renderHeader();
    clear(body);
    if (cards.length === 0) {
      body.appendChild(emptyState(icon("style", 46), t("Nothing to Practice"),
        t("Add some words to a list first, then come back to review them.")));
    } else if (session.length === 0) {
      renderSetup();
    } else if (finished) {
      renderSummary();
    } else {
      renderPractice();
    }
  }

  function renderSetup() {
    const due = dueCount();
    const modeList = el(".check-card");
    for (const mode of FRONT_MODES) {
      const on = selectedModes.has(mode.id);
      modeList.appendChild(el(".check-row", {
        onclick: () => { on ? selectedModes.delete(mode.id) : selectedModes.add(mode.id); render(); },
      }, el(".radio" + (on ? ".on" : ""), {}, on ? icon("check", 16) : null), el("span", {}, t(mode.labelKey))));
    }
    const dailyToggle = el(".toggle-row", {},
      el("span", {}, t("Daily assignment")),
      el(".switch" + (dueOnly ? ".on" : ""), { onclick: () => { dueOnly = !dueOnly; render(); } }, el(".knob")),
    );
    body.appendChild(el(".practice-setup", {},
      el(".big-icon", {}, icon("style", 52)),
      el("h2", {}, t("Ready to practice?")),
      el("p.muted", {}, due > 0 ? tn("%lld cards due for review.", due) : t("You finished your daily assignment.")),
      el(".setup-card", {},
        dailyToggle,
        el(".section-label", {}, t("Show first")),
        modeList,
        selectedModes.has("pronunciation") ? el(".form-note", {}, t("Audio is only used for words with a recorded pronunciation.")) : null,
      ),
      el("button.btn.primary.large", { disabled: deck().length === 0, onclick: start }, t("Start Session")),
    ));
  }

  function start() {
    const d = deck();
    if (d.length === 0) return;
    session = d; totalCards = d.length; index = 0; correctCount = 0; isFlipped = false; finished = false;
    render();
  }

  function renderPractice() {
    const item = session[index];
    const word = item.card.word;
    const mode = item.mode;
    const frontIsPron = mode === "pronunciation";
    const termReading = M.readingFor(word, learningLanguage);
    const posLabels = M.partOfSpeechValues(word).map((p) => M.posLabel(p, preferredLanguage()));

    const card = el(".flashcard" + (isFlipped ? ".flipped" : ""), {
      onclick: () => { isFlipped = !isFlipped; render(); },
    });
    card.appendChild(el(".card-corner", {}, isFlipped ? t("Answer") : t("Tap to flip")));
    if (isFlipped) {
      card.appendChild(el(".card-answer", {},
        el(".answer-term", {}, word.term),
        termReading ? el(".answer-reading", {}, termReading) : null,
        posLabels.length ? el(".chip-row", {}, ...posLabels.map((p) => el(".chip", {}, p))) : null,
        el("hr"),
        el(".answer-translation", {}, word.translation),
        word.notes ? el(".answer-notes", {}, word.notes) : null,
      ));
    } else if (frontIsPron) {
      card.appendChild(el(".card-front-pron", {}, el(".big-icon", {}, icon("volume_up", 52)), el("p.muted", {}, t("Listen and recall"))));
    } else {
      card.appendChild(el(".card-prompt", {}, mode === "translation" ? word.translation : word.term));
    }

    const showAudio = (frontIsPron ? !isFlipped : isFlipped) && word.audioPath;

    body.appendChild(el(".practice-view", {},
      el(".progress-track", {}, el(".progress-fill", { style: `width:${(index / session.length) * 100}%` })),
      el("p.caption.center", {}, tf("%lld of %lld", index + 1, session.length)),
      card,
      showAudio ? playbackButton(word.audioPath, true) : el(".audio-placeholder"),
      isFlipped
        ? el(".answer-actions", {},
            el("button.btn.warn.large", { onclick: () => answer(false) }, icon("replay", 20), t("Practice Again")),
            el("button.btn.good.large", { onclick: () => answer(true) }, icon("check", 20), t("Got It")),
          )
        : el("p.muted.center", {}, t("Tap the card to reveal the answer")),
    ));
  }

  function answer(correct) {
    const item = session[index];
    if (dueOnly) {
      if (correct) { M.markCorrect(item.card.word, item.mode === "term" ? "spelling" : item.mode === "translation" ? "translation" : "pronunciation");
        Repo.recordRemembered(authState.uid, item.mode === "term" ? "spelling" : item.mode === "translation" ? "translation" : "pronunciation").catch(() => {});
      } else {
        M.markIncorrect(item.card.word, item.mode === "term" ? "spelling" : item.mode === "translation" ? "translation" : "pronunciation");
      }
      // keep copies in sync
      for (const s of session) if (s.card.word.id === item.card.word.id) s.card.word = item.card.word;
      Repo.updateWord(authState.uid, item.card.listId, item.card.word).catch(() => {});
    }
    if (correct) correctCount += 1;
    else session.push(item);
    isFlipped = false;
    if (index + 1 < session.length) index += 1; else finished = true;
    render();
  }

  function renderSummary() {
    body.appendChild(el(".practice-summary", {},
      el(".big-icon.good", {}, icon("check_circle", 64)),
      el("h2", {}, t("Session Complete!")),
      el("p.muted", {}, tf("You got %lld of %lld right.", correctCount, totalCards)),
      el("button.btn.primary.large", { onclick: () => { session = []; index = 0; correctCount = 0; finished = false; render(); } }, t("Done")),
    ));
  }

  render();
}

// MARK: - Stats screen

async function StatsScreen(content) {
  content.appendChild(navBar(t("Statistics"), {}));
  const body = el(".scroll");
  content.appendChild(body);
  body.appendChild(spinner(t("Loading…")));

  let words = [];
  let dailyStats = [];
  try {
    const lists = await Repo.fetchLists(authState.uid);
    for (const l of lists) words = words.concat(await Repo.fetchWords(authState.uid, l.id));
    dailyStats = await Repo.fetchDailyStats(authState.uid, 7).catch(() => []);
  } catch (e) { clear(body); body.appendChild(errorState(e)); return; }

  clear(body);
  if (words.length === 0) {
    body.appendChild(emptyState(icon("bar_chart", 46), t("No Stats Yet"),
      t("Add words and practice them. Once you've memorized some, your progress shows up here.")));
    return;
  }

  // Aggregate stats (LearningStats). A word counts as memorized only once it is
  // fully remembered: 8× word, 10× translation, 7× pronunciation (remember_final).
  const totalWords = words.length;
  const totalMemorized = words.filter(M.isRemembered).length;
  const dates = words.map((w) => w.createdAt).filter(Boolean);
  const start = dates.length ? new Date(Math.min(...dates.map((d) => +d))) : null;
  let activeDays = 1;
  if (start) {
    const s = new Date(start); s.setHours(0, 0, 0, 0);
    const n = new Date(); n.setHours(0, 0, 0, 0);
    activeDays = Math.max(1, Math.round((n - s) / 86400000) + 1);
  }
  const perDay = totalMemorized / activeDays;
  const perWeek = perDay * 7;
  const perMonth = perDay * (365.25 / 12);

  // Today remembered (derived from words)
  const today = { word: 0, translation: 0, pronunciation: 0 };
  for (const w of words) {
    if (M.isToday(w.lastWordRemembered)) today.word += 1;
    if (M.isToday(w.lastTranslationRemembered)) today.translation += 1;
    if (M.isToday(w.lastPronounciationRemembered)) today.pronunciation += 1;
  }

  const aspectKeys = ["word", "translation", "pronunciation"];
  const aspectLabel = (k) => k === "word" ? t("Word") : k === "translation" ? t("Translation") : t("Pronunciation");
  const colors = { word: "#2f6bff", translation: "#1fb56a", pronunciation: "#ff8a1f" };

  body.appendChild(el(".stats", {},
    // total card
    el(".stat-total", {},
      el(".big-icon", {}, icon("psychology", 44)),
      el(".stat-number", {}, `${totalMemorized}`),
      el(".stat-caption", {}, t("words memorized")),
      el(".stat-subcaption", {}, tf("out of %lld total", totalWords)),
    ),
    el(".stat-block", {},
      el("h3", {}, t("Remembered today")),
      barChart(aspectKeys.map((k) => ({ label: aspectLabel(k), value: today[k], color: colors[k] }))),
    ),
    el(".stat-block", {},
      el("h3", {}, t("This week")),
      weekChart(dailyStats, today, aspectKeys, aspectLabel, colors),
    ),
    el(".stat-block", {},
      el("h3", {}, t("Average pace")),
      el(".pace-row", {},
        paceCard(t("Per day"), perDay),
        paceCard(t("Per week"), perWeek),
        paceCard(t("Per month"), perMonth),
      ),
    ),
    start ? el("p.caption.center", {},
      tf("Based on %lld days of learning since %@.", activeDays, start.toLocaleDateString(i18n.preferredLanguage()))) : null,
  ));

  function paceCard(title, value) {
    const text = value < 10 ? value.toFixed(1) : `${Math.round(value)}`;
    return el(".pace-card", {}, el(".pace-value", {}, text), el(".pace-title", {}, title));
  }
}

function barChart(bars) {
  const W = 320, H = 200, pad = 28;
  const max = Math.max(1, ...bars.map((b) => b.value));
  const bw = (W - pad * 2) / bars.length;
  const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart", preserveAspectRatio: "xMidYMid meet" });
  bars.forEach((b, i) => {
    const h = (b.value / max) * (H - pad * 2);
    const x = pad + i * bw + bw * 0.2;
    const w = bw * 0.6;
    const y = H - pad - h;
    svg.appendChild(svgEl("rect", { x, y, width: w, height: h, rx: 6, fill: b.color }));
    svg.appendChild(svgEl("text", { x: x + w / 2, y: y - 6, "text-anchor": "middle", class: "chart-val" }, document.createTextNode(`${b.value}`)));
    const label = svgEl("text", { x: x + w / 2, y: H - 8, "text-anchor": "middle", class: "chart-lbl" });
    label.appendChild(document.createTextNode(b.label));
    svg.appendChild(label);
  });
  return svg;
}

function weekChart(dailyStats, today, aspectKeys, aspectLabel, colors) {
  const W = 340, H = 220, padX = 24, padY = 28;
  const byDate = {};
  for (const s of dailyStats) byDate[s.date] = s;
  const days = [];
  const now = new Date(); now.setHours(0, 0, 0, 0);
  for (let off = 6; off >= 0; off--) {
    const d = new Date(now); d.setDate(d.getDate() - off);
    const key = Repo.dayKey(d);
    const stat = byDate[key];
    const vals = {};
    for (const k of aspectKeys) {
      vals[k] = off === 0 ? (today[k] || 0) : (stat ? (stat[k] || 0) : 0);
    }
    days.push({ date: d, vals });
  }
  const max = Math.max(1, ...days.flatMap((d) => aspectKeys.map((k) => d.vals[k])));
  const innerW = W - padX * 2, innerH = H - padY * 2;
  const x = (i) => padX + (i / 6) * innerW;
  const y = (v) => padY + innerH - (v / max) * innerH;
  const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart", preserveAspectRatio: "xMidYMid meet" });
  // gridlines + weekday labels
  days.forEach((d, i) => {
    svg.appendChild(svgEl("line", { x1: x(i), y1: padY, x2: x(i), y2: padY + innerH, stroke: "#e6e6ec", "stroke-width": 1, "stroke-dasharray": "4 4" }));
    const lbl = svgEl("text", { x: x(i), y: H - 8, "text-anchor": "middle", class: "chart-lbl" });
    lbl.appendChild(document.createTextNode(d.date.toLocaleDateString(i18n.preferredLanguage(), { weekday: "narrow" })));
    svg.appendChild(lbl);
  });
  for (const k of aspectKeys) {
    const pts = days.map((d, i) => `${x(i)},${y(d.vals[k])}`).join(" ");
    svg.appendChild(svgEl("polyline", { points: pts, fill: "none", stroke: colors[k], "stroke-width": 2.5, "stroke-linejoin": "round", "stroke-linecap": "round" }));
    days.forEach((d, i) => svg.appendChild(svgEl("circle", { cx: x(i), cy: y(d.vals[k]), r: 3, fill: colors[k] })));
  }
  // legend
  const legend = el(".chart-legend", {}, ...aspectKeys.map((k) =>
    el(".legend-item", {}, el(".legend-dot", { style: `background:${colors[k]}` }), aspectLabel(k))));
  return el(".chart-wrap", {}, svg, legend);
}

// MARK: - Settings screen

function SettingsScreen(content) {
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
      el("button.form-action.danger", {
        onclick: () => confirmDialog({
          message: t("Sign out of Retainic?"), confirmLabel: t("Sign Out"), danger: true,
          onConfirm: () => Auth.signOut(),
        }),
      }, t("Sign Out")))),
  ));
}

// MARK: - About screen

function AboutScreen(content) {
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

// MARK: - Small shared pieces

function playbackButton(path, large = false) {
  const btn = el("button.audio-btn" + (large ? ".large" : ""), {}, speakerGlyph());
  const update = (playingPath) => {
    const playing = playingPath === path;
    clear(btn);
    btn.appendChild(playing ? stopGlyph() : speakerGlyph());
    if (large) btn.appendChild(document.createTextNode(" " + (playing ? t("Stop") : t("Play pronunciation"))));
  };
  btn.addEventListener("click", (e) => { e.stopPropagation(); playback.toggle(path); });
  const unsub = playback.subscribe(update);
  update(playback.playingPath);
  // Clean up subscription when removed (best-effort)
  return btn;
}

function labeledRow(label, value) {
  return el(".labeled-row", {}, el("span.lr-label", {}, label), el("span.lr-value", {}, value));
}
function pickerRow(label, select) {
  return el(".picker-row", {}, el("span", {}, label), select);
}
function formSection(title, ...cards) {
  return el(".form-section", {}, title ? el(".section-title", {}, title) : null, ...cards.filter(Boolean));
}
function sheetHeader(title, api, confirmBtn, cancelLabel) {
  return el(".sheet-header", {},
    el(".sheet-side", {}, cancelLabel === null ? null : textButton(cancelLabel || t("Cancel"), () => api.close())),
    el(".sheet-title", {}, title),
    el(".sheet-side.trailing", {}, confirmBtn),
  );
}
function errorState(e) {
  return emptyState(icon("error", 46), t("Something went wrong"), Auth.friendlyMessage(e));
}

/** An in-app confirmation panel (replaces the browser's native confirm()). */
function confirmDialog({ message, confirmLabel, danger = false, onConfirm }) {
  presentSheet((api) => el(".confirm", {},
    el(".confirm-msg", {}, message),
    el(".confirm-actions", {},
      el("button.btn.subtle", { onclick: () => api.close() }, t("Cancel")),
      el("button.btn." + (danger ? "destructive" : "primary"), {
        onclick: () => { api.close(); onConfirm(); },
      }, confirmLabel || t("OK")),
    ),
  ), { variant: "alert" });
}

// MARK: - Icons (Google Material Symbols)

/** A Material Symbols glyph. `name` is the symbol's ligature name; `size` (px)
 *  is optional and otherwise inherits from the context. */
function icon(name, size) {
  const s = el("span.msym", {}, name);
  if (size) s.style.fontSize = size + "px";
  return s;
}
function bookIcon(size = 24) { return icon("menu_book", size); }
function glyph(name) {
  const map = { person: "person", envelope: "mail", lock: "lock", key: "key" };
  return icon(map[name] || "circle", 20);
}
function listsGlyph() { return icon("view_list", 24); }
function chartGlyph(size = 24) { return icon("bar_chart", size); }
function gearGlyph() { return icon("settings", 24); }
function rectStackGlyph() { return icon("stacks", 24); }
function bookClosedGlyph() { return icon("menu_book", 24); }
function speakerGlyph() { return icon("volume_up", 18); }
function stopGlyph() { return icon("stop", 18); }
