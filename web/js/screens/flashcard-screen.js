//
//  Flashcard setup, practice session, and result summary.
//  Retainic Web
//

import { el, clear, toast } from "../dom.js";
import { t, tn, tf, preferredLanguage } from "../i18n.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import { authState } from "../auth.js";
import { playback } from "../audio.js";
import { useAlgorithm, useDefaultAlgorithm } from "../algorithm.js";
import { reviewWeight, weightedOrder } from "../review-order.js";
import { navBar, iconButton, spinner, emptyState, pronunciationButton, icon } from "../ui.js";

const FRONT_MODES = [
  { id: "term", labelKey: "Word", aspect: "spelling" },
  { id: "translation", labelKey: "Translation", aspect: "translation" },
  { id: "pronunciation", labelKey: "Audio", aspect: "pronunciation" },
];

const aspectForMode = (modeId) => FRONT_MODES.find((mode) => mode.id === modeId)?.aspect || null;

export function FlashcardScreen(content, cards, learningLanguage, ttsEnabled = false, algorithmCode = null, onBack) {
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

  // A custom algorithm must be compiled (loading Pyodide the first time) before
  // scheduling can run. Lists on the default schedule are ready immediately.
  const hasCustomAlgorithm = !!(algorithmCode && algorithmCode.trim());
  let algoReady = !hasCustomAlgorithm;
  if (hasCustomAlgorithm) {
    useAlgorithm(algorithmCode)
      .catch((e) => { toast(t("Couldn't run your algorithm — using the default.")); })
      .finally(() => { algoReady = true; render(); });
  } else {
    useDefaultAlgorithm();
  }

  function includes(card, modeId) {
    // Pronunciation practice needs something to hear: a recording, or a
    // synthesized voice when the list has text-to-speech enabled.
    if (modeId === "pronunciation" && card.word.audioPath == null && !ttsEnabled) return false;
    if (dueOnly) {
      if (modeId === "translation") return M.isTranslationDue(card.word, new Date(), ttsEnabled);
      if (modeId === "term") return M.isWordDue(card.word, new Date(), ttsEnabled);
      return M.isPronunciationDue(card.word, new Date(), ttsEnabled);
    }
    return card.word.remember_final !== true;
  }
  function deck() {
    if (selectedModes.size === 0) return [];
    const items = [];
    for (const mode of selectedModes) {
      for (const card of cards) {
        if (!includes(card, mode)) continue;
        const facts = M.factValues(card.word);
        const promptIndex = mode === "pronunciation" ? null
          : mode === "term" ? 0
          : facts.length ? Math.floor(Math.random() * facts.length) : 0;
        items.push({ card, mode, promptIndex });
      }
    }
    return weightedOrder(items, (item) =>
      reviewWeight(item.card.word, aspectForMode(item.mode)));
  }
  function dueCount() {
    let sum = 0;
    for (const mode of selectedModes) sum += cards.filter((c) => includes(c, mode)).length;
    return sum;
  }

  function renderHeader() {
    clear(header);
    header.appendChild(navBar(t("Practice"), {
      leading: iconButton(icon("arrow_back", 22), () => {
        playback.stop();
        // Mid-session, the back button ends the session and shows the summary
        // (results) instead of dropping straight back to the word list.
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
        (selectedModes.has("pronunciation") && !ttsEnabled) ? el(".form-note", {}, t("Audio is only used for words with a recorded pronunciation.")) : null,
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
    const presentation = M.recallPresentation(word, item.promptIndex);
    const prompt = presentation.prompt;
    const termIsAnswer = presentation.answerTerm != null;
    const answerFacts = presentation.answerFacts;
    const termReading = M.readingFor(word, learningLanguage);
    const posLabels = M.partOfSpeechValues(word).map((p) => M.posLabel(p, preferredLanguage()));

    const card = el(".flashcard" + (isFlipped ? ".flipped" : ""), {
      onclick: () => { isFlipped = !isFlipped; render(); },
    });
    card.appendChild(el(".card-corner", {}, isFlipped ? t("Answer") : t("Tap to flip")));
    if (isFlipped) {
      const answer = el(".card-answer");
      if (termIsAnswer) {
        answer.appendChild(el(".answer-term", {}, word.term));
        if (termReading) answer.appendChild(el(".answer-reading", {}, termReading));
        if (posLabels.length) answer.appendChild(el(".chip-row", {}, ...posLabels.map((p) => el(".chip", {}, p))));
      }
      if (termIsAnswer && answerFacts.length) answer.appendChild(el("hr"));
      if (answerFacts.length) {
        answer.appendChild(el(".answer-facts", {},
          ...answerFacts.map((fact) => el(".answer-translation", {}, fact))));
      }
      if (word.notes) answer.appendChild(el(".answer-notes", {}, word.notes));
      card.appendChild(answer);
    } else if (frontIsPron) {
      card.appendChild(el(".card-front-pron", {}, el(".big-icon", {}, icon("volume_up", 52)), el("p.muted", {}, t("Listen and recall"))));
    } else {
      card.appendChild(el(".card-prompt", {}, prompt));
    }

    const showAudioSide = frontIsPron ? !isFlipped : isFlipped;
    const pronBtn = showAudioSide ? pronunciationButton(word, { learningLanguage, ttsEnabled }, true) : null;

    body.appendChild(el(".practice-view", {},
      el(".progress-track", {}, el(".progress-fill", { style: `width:${(index / session.length) * 100}%` })),
      el("p.caption.center", {}, tf("%lld of %lld", index + 1, session.length)),
      card,
      pronBtn || el(".audio-placeholder"),
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
    const aspect = aspectForMode(item.mode);
    if (dueOnly) {
      if (correct) { M.markCorrect(item.card.word, aspect, ttsEnabled);
        Repo.recordRemembered(authState.uid, aspect).catch(() => {});
      } else {
        M.markIncorrect(item.card.word, aspect);
      }
      // keep copies in sync
      for (const s of session) if (s.card.word.id === item.card.word.id) s.card.word = item.card.word;
      Repo.updateWord(authState.uid, item.card.listId, item.card.word, { ttsEnabled }).catch(() => {});
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
