//
//  Add and edit word flow.
//  Retainic Web
//

import { el, clear, presentSheet, toast } from "../dom.js";
import { t, displayNameIn, preferredLanguage } from "../i18n.js";
import * as Repo from "../repository.js";
import * as M from "../models.js";
import * as Auth from "../auth.js";
import { authState } from "../auth.js";
import { PronunciationRecorder } from "../audio.js";
import { icon, iconButton, formSection, confirmDialog } from "../ui.js";

export function presentWordSheet({ list, word, onSaved }) {
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
    let factInputs = (word ? M.translationValues(word) : [""]).map(makeFactInput);
    if (factInputs.length === 0) factInputs = [makeFactInput("")];
    const factsCard = el(".form-card");
    const notes = el("textarea.field-input", { rows: 3, placeholder: t("Example sentence or memory hint") }, word?.notes || "");
    const errorEl = el(".form-footer-error");
    const pinyinFooter = el(".form-note");
    const saveBtn = el("button.icon-btn", { onclick: save, title: t("Save"), "aria-label": t("Save") }, icon("check", 24));

    function makeFactInput(value) {
      const input = el("input.field-input", { type: "text", value, placeholder: t("Translation") });
      input.addEventListener("input", validate);
      return input;
    }
    function factValues() {
      return factInputs.map((input) => input.value.trim()).filter(Boolean);
    }
    function renderFacts() {
      clear(factsCard);
      factInputs.forEach((input, index) => {
        const remove = factInputs.length > 1
          ? iconButton(icon("remove_circle", 20), () => {
              factInputs.splice(index, 1);
              renderFacts();
              validate();
            }, { label: t("Delete"), danger: true })
          : null;
        factsCard.appendChild(el(".row", {}, input, remove));
      });
      factsCard.appendChild(el("button.form-action", {
        onclick: () => {
          const input = makeFactInput("");
          factInputs.push(input);
          renderFacts();
          input.focus();
          validate();
        },
      }, icon("add", 20), t("Add")));
    }

    function validate() {
      const filled = term.value.trim() && factValues().length > 0 && (!isZh || pinyin.value.trim());
      const ok = filled && hasChanges();
      saveBtn.disabled = !ok;
      saveBtn.classList.toggle("disabled", !ok);
      if (isZh) pinyinFooter.innerHTML = pinyin.value.trim() ? "" : `<span class="danger-text">${t("Pinyin is required for Chinese words.")}</span>`;
    }
    // When editing, Save stays disabled until something actually changes.
    function hasChanges() {
      if (!isEditing) return true;
      if (term.value.trim() !== (word.term || "")) return true;
      const currentFacts = factValues();
      const originalFacts = M.translationValues(word);
      if (currentFacts.length !== originalFacts.length || currentFacts.some((value, index) => value !== originalFacts[index])) return true;
      if (notes.value.trim() !== (word.notes || "")) return true;
      if (hiragana.value.trim() !== (word.hiragana || "")) return true;
      if (pinyin.value.trim() !== (word.pinyin || "")) return true;
      const origPOS = new Set(M.partOfSpeechValues(word));
      if (origPOS.size !== selectedPOS.size) return true;
      for (const p of selectedPOS) if (!origPOS.has(p)) return true;
      if (recorder.recordedBlob) return true;              // new recording
      if (word.audioPath && !recorder.hasAudio) return true; // removed audio
      return false;
    }
    [term, pinyin, hiragana, notes].forEach((i) => i.addEventListener("input", validate));

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
      validate();
    }
    const pronNote = el(".form-note");

    // POS section
    const posHost = el(".form-card");
    function renderPOS() {
      clear(posHost);
      for (const p of M.PARTS_OF_SPEECH) {
        const on = selectedPOS.has(p);
        posHost.appendChild(el(".check-row", {
          onclick: () => { on ? selectedPOS.delete(p) : selectedPOS.add(p); renderPOS(); validate(); },
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
          const facts = factValues();
          w.translation = facts[0];
          w.translations = facts;
          w.notes = notes.value.trim();
          w.partsOfSpeech = posList;
          w.partOfSpeech = null;
          w.hiragana = hiragana.value.trim() || null;
          w.pinyin = pinyin.value.trim() || null;
          await Repo.updateWord(authState.uid, list.id, w, { audioBlob, removeAudio, ttsEnabled: list.ttsEnabled === true });
        } else {
          const w = M.newWord({
            term: term.value.trim(),
            translations: factValues(),
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

    function deleteThisWord() {
      confirmDialog({
        message: t("Delete this word?"), confirmLabel: t("Delete"), danger: true,
        onConfirm: async () => {
          try {
            recorder.stopPlayback();
            await Repo.deleteWord(authState.uid, list.id, word.id);
            api.close();
            onSaved();
          } catch (e) { toast(Auth.friendlyMessage(e)); }
        },
      });
    }

    renderFacts();
    setTimeout(validate, 0);
    const learnTitle = displayNameIn(learning) || t("Word");
    const origTitle = displayNameIn(original) || t("Translation");

    return el(".sheet-content", {},
      el(".sheet-header", {},
        el(".sheet-side", {}, isEditing ? null : el("button.icon-btn", {
          onclick: () => api.close(), title: t("Cancel"), "aria-label": t("Cancel"),
        }, icon("close", 24))),
        el(".sheet-title", {}, isEditing ? t("Edit Word") : t("New Word")),
        el(".sheet-side.trailing", {}, saveBtn),
      ),
      el(".form", {},
        formSection(learnTitle, el(".form-card", {}, term)),
        isJa ? formSection(t("Hiragana (optional)"), el(".form-card", {}, hiragana)) : null,
        isZh ? formSection(t("Pinyin (required)"), el(".form-card", {}, pinyin), pinyinFooter) : null,
        formSection(origTitle, factsCard),
        formSection(t("Part of speech"), posHost, el(".form-note", {}, t("Select all that apply."))),
        formSection(t("Pronunciation (optional)"), pronHost, pronNote),
        formSection(t("Notes (optional)"), el(".form-card", {}, notes)),
        isEditing ? formSection(null, el(".form-card", {},
          el("button.form-action.danger", { onclick: deleteThisWord }, icon("delete", 20), t("Delete Word")))) : null,
        errorEl,
      ),
    );
  });
}
