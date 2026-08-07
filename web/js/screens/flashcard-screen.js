//
//  Flashcard setup, practice session, and result summary.
//  Retainic Web
//
//  One session engine drives two kinds of deck — a vocabulary list's words and
//  a glossary's terms. Everything specific to a kind (which methods can be
//  practised, what each card side shows, how a grade is recorded) lives in the
//  deck adapter built by `deckFor`; the rest of the screen is shared.
//

import { el, clear, toast } from "../dom.js";
import { t, tn, tf, preferredLanguage } from "../i18n.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import * as G from "../glossary.js";
import { authState } from "../auth.js";
import { playback } from "../audio.js";
import { useAlgorithm, useDefaultAlgorithm } from "../algorithm.js";
import { navBar, iconButton, spinner, emptyState, pronunciationButton, icon } from "../ui.js";

const WORD_MODES = [
  { id: "term", labelKey: "Word", aspect: "spelling" },
  { id: "translation", labelKey: "Translation", aspect: "translation" },
  { id: "pronunciation", labelKey: "Audio", aspect: "pronunciation" },
];

const GLOSSARY_MODES = [
  { id: "term", labelKey: "Term", aspect: "term", dailyAspect: "spelling" },
  { id: "definition", labelKey: "Definition", aspect: "definition", dailyAspect: "translation" },
];

/** Adapter for a vocabulary list's words. */
function wordDeck({ learningLanguage = "", ttsEnabled = false, algorithmCode = null }) {
  const tts = ttsEnabled === true;
  const list = { learningLanguage, ttsEnabled: tts };
  /** Whether a word belongs in the deck for a method: in the daily assignment
   *  that method must be due; in free practice every unmemorized word counts. */
  function includes(card, modeId, dueOnly) {
    // Pronunciation practice needs something to hear: a recording, or a
    // synthesized voice when the list has text-to-speech enabled.
    if (modeId === "pronunciation" && card.word.audioPath == null && !tts) return false;
    if (!dueOnly) return card.word.remember_final !== true;
    if (modeId === "translation") return M.isTranslationDue(card.word, new Date(), tts);
    if (modeId === "term") return M.isWordDue(card.word, new Date(), tts);
    return M.isPronunciationDue(card.word, new Date(), tts);
  }
  return {
    modes: WORD_MODES,
    emptyDescription: t("Add some words to a list first, then come back to review them."),
    // A custom algorithm must be compiled (loading Pyodide the first time)
    // before scheduling can run. Lists on the default schedule are ready
    // immediately, as are glossaries — they always use the built-in schedule.
    prepare() {
      if (!(algorithmCode && algorithmCode.trim())) { useDefaultAlgorithm(); return null; }
      return useAlgorithm(algorithmCode)
        .catch(() => { toast(t("Couldn't run your algorithm — using the default.")); });
    },
    // A word is one card per method, so the deck holds it or it doesn't.
    parts(card, modeId, dueOnly) {
      return includes(card, modeId, dueOnly) ? [{}] : [];
    },
    front({ card, mode }) {
      const word = card.word;
      if (mode.id === "pronunciation") {
        return el(".card-front-pron", {}, el(".big-icon", {}, icon("volume_up", 52)), el("p.muted", {}, t("Listen and recall")));
      }
      return el(".card-prompt", {}, mode.id === "translation" ? word.translation : word.term);
    },
    back({ card }) {
      const word = card.word;
      const termReading = M.readingFor(word, learningLanguage);
      const posLabels = M.partOfSpeechValues(word).map((p) => M.posLabel(p, preferredLanguage()));
      return el(".card-answer", {},
        el(".answer-term", {}, word.term),
        termReading ? el(".answer-reading", {}, termReading) : null,
        posLabels.length ? el(".chip-row", {}, ...posLabels.map((p) => el(".chip", {}, p))) : null,
        el("hr"),
        el(".answer-translation", {}, word.translation),
        word.notes ? el(".answer-notes", {}, word.notes) : null,
      );
    },
    // The audio control belongs with the side that isn't the prompt: on the
    // back of a normal card, on the front when listening is the prompt.
    audioSide(modeId, isFlipped) {
      return modeId === "pronunciation" ? !isFlipped : isFlipped;
    },
    audioControl(card) {
      return pronunciationButton(card.word, list, true);
    },
    grade({ card, mode }, correct) {
      if (correct) M.markCorrect(card.word, mode.aspect, tts);
      else M.markIncorrect(card.word, mode.aspect);
      if (correct) Repo.recordRemembered(authState.uid, mode.aspect).catch(() => {});
      Repo.updateWord(authState.uid, card.listId, card.word, { ttsEnabled: tts }).catch(() => {});
    },
    sameCard(a, b) { return a.word.id === b.word.id; },
    syncCard(target, source) { target.word = source.word; },
  };
}

/** Adapter for a glossary's entries: term and definitions, no audio, always the
 *  built-in schedule. A term that means several things is one card per meaning
 *  when the definition is shown first — each definition has its own schedule —
 *  and a single card the other way round, revealing them all. */
function glossaryDeck() {
  return {
    modes: GLOSSARY_MODES,
    emptyDescription: t("Add some terms to a glossary first, then come back to review them."),
    prepare() { useDefaultAlgorithm(); return null; },
    parts(card, modeId, dueOnly) {
      const entry = card.entry;
      if (modeId === "term") {
        if (dueOnly) return G.isTermDue(entry) ? [{}] : [];
        return entry.remember_final !== true ? [{}] : [];
      }
      const indexes = dueOnly
        ? G.dueDefinitionIndexes(entry)
        : (entry.remember_final !== true ? G.definitionTexts(entry).map((_, i) => i) : []);
      return indexes.map((definitionIndex) => ({ definitionIndex }));
    },
    front({ card, mode, definitionIndex }) {
      const entry = card.entry;
      if (mode.id !== "definition") return el(".card-prompt", {}, entry.term);
      return el(".card-prompt", {}, G.definitionTexts(entry)[definitionIndex] ?? "");
    },
    back({ card }) {
      const entry = card.entry;
      const texts = G.definitionTexts(entry);
      return el(".card-answer", {},
        el(".answer-term", {}, entry.term),
        el("hr"),
        // Whichever definition was the prompt, the answer side shows the term
        // with everything it can mean.
        texts.length > 1
          ? el("ol.answer-definitions", {}, ...texts.map((text) => el("li", {}, text)))
          : el(".answer-translation", {}, texts[0] ?? ""),
        entry.notes ? el(".answer-notes", {}, entry.notes) : null,
      );
    },
    audioSide() { return false; },
    audioControl() { return null; },
    grade({ card, mode, definitionIndex }, correct) {
      if (correct) G.markCorrect(card.entry, mode.aspect, definitionIndex ?? 0);
      else G.markIncorrect(card.entry, mode.aspect);
      if (correct) Repo.recordRemembered(authState.uid, mode.dailyAspect).catch(() => {});
      Repo.updateEntry(authState.uid, card.glossaryId, card.entry).catch(() => {});
    },
    sameCard(a, b) { return a.entry.id === b.entry.id; },
    syncCard(target, source) { target.entry = source.entry; },
  };
}

function deckFor(ctx) {
  return ctx.kind === "glossary" ? glossaryDeck(ctx) : wordDeck(ctx);
}

/** `ctx` is the practice context a detail screen handed to the shell:
 *  `{ cards, kind }` plus whatever that kind needs (a list passes its
 *  learning language, text-to-speech setting, and custom algorithm). */
export function FlashcardScreen(content, ctx, onBack) {
  const deck = deckFor(ctx);
  const cards = ctx.cards || [];
  const header = el(".navbar-host");
  const body = el(".scroll");
  content.appendChild(header);
  content.appendChild(body);

  let session = [];   // [{ card, mode, ...deck extras }]
  let index = 0;
  let isFlipped = false;
  let selectedModes = new Set(["term"]);
  let correctCount = 0;
  let totalCards = 0;
  let dueOnly = true;
  let finished = false;

  const preparing = deck.prepare();
  let algoReady = !preparing;
  if (preparing) preparing.finally(() => { algoReady = true; render(); });

  const modeById = (id) => deck.modes.find((m) => m.id === id);

  /** The session items one method contributes. A card is usually one item, but
   *  a deck can split it into several — a glossary term with five definitions
   *  is five definition-first cards. */
  function items(modeId) {
    const mode = modeById(modeId);
    const out = [];
    for (const card of cards)
      for (const part of deck.parts(card, modeId, dueOnly)) out.push({ card, mode, ...part });
    return out;
  }
  function buildSession() {
    if (selectedModes.size === 0) return [];
    const out = [];
    for (const modeId of selectedModes) out.push(...items(modeId));
    // shuffle
    for (let i = out.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [out[i], out[j]] = [out[j], out[i]]; }
    return out;
  }
  function dueCount() {
    let sum = 0;
    for (const modeId of selectedModes) sum += items(modeId).length;
    return sum;
  }

  function renderHeader() {
    clear(header);
    header.appendChild(navBar(t("Practice"), {
      leading: iconButton(icon("arrow_back", 22), () => {
        playback.stop();
        // Mid-session, the back button ends the session and shows the summary
        // (results) instead of dropping straight back to the entry list.
        if (session.length && !finished) { finished = true; render(); }
        else { onBack(); }
      }, { label: "Back" }),
    }));
  }

  function render() {
    renderHeader();
    clear(body);
    if (!algoReady) {
      body.appendChild(spinner(t("Preparing your algorithm…")));
    } else if (cards.length === 0) {
      body.appendChild(emptyState(icon("style", 46), t("Nothing to Practice"), deck.emptyDescription));
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
    for (const mode of deck.modes) {
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
        (selectedModes.has("pronunciation") && ctx.ttsEnabled !== true) ? el(".form-note", {}, t("Audio is only used for words with a recorded pronunciation.")) : null,
      ),
      el("button.btn.primary.large", { disabled: buildSession().length === 0, onclick: start }, t("Start Session")),
    ));
  }

  function start() {
    const d = buildSession();
    if (d.length === 0) return;
    session = d; totalCards = d.length; index = 0; correctCount = 0; isFlipped = false; finished = false;
    render();
  }

  function renderPractice() {
    const item = session[index];
    const card = el(".flashcard" + (isFlipped ? ".flipped" : ""), {
      onclick: () => { isFlipped = !isFlipped; render(); },
    });
    card.appendChild(el(".card-corner", {}, isFlipped ? t("Answer") : t("Tap to flip")));
    card.appendChild(isFlipped ? deck.back(item) : deck.front(item));

    const audioBtn = deck.audioSide(item.mode.id, isFlipped) ? deck.audioControl(item.card) : null;

    body.appendChild(el(".practice-view", {},
      el(".progress-track", {}, el(".progress-fill", { style: `width:${(index / session.length) * 100}%` })),
      el("p.caption.center", {}, tf("%lld of %lld", index + 1, session.length)),
      card,
      audioBtn || el(".audio-placeholder"),
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
    // Only the daily assignment counts: free practice never changes a schedule.
    if (dueOnly) {
      deck.grade(item, correct);
      // keep copies in sync
      for (const s of session) if (deck.sameCard(s.card, item.card)) deck.syncCard(s.card, item.card);
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
