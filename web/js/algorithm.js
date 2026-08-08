//
//  algorithm.js
//  Retainic Web
//
//  Pluggable review algorithm. A list — or a glossary — may override the
//  spaced-repetition schedule with its own Python, executed in the browser via
//  Pyodide (real CPython compiled to WebAssembly, loaded on demand from a CDN).
//  Compiling a snippet installs it as the active algorithm in models.js (words)
//  or glossary.js (terms); with no override the built-in JS default runs and
//  Pyodide is never loaded.
//
//  The two kinds have their own contract, because a word has three methods and
//  one meaning while a term has two methods and any number of meanings.
//

import { setActiveAlgorithm } from "./models.js";
import { setActiveGlossaryAlgorithm } from "./glossary.js";

const PYODIDE_VERSION = "0.26.4";
const PYODIDE_URL = `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_VERSION}/full/pyodide.mjs`;

/** The default algorithm, shown pre-filled in the editor. Mirrors the built-in
 *  schedule exactly, so saving it unchanged behaves like having no override. */
export const DEFAULT_ALGORITHM_CODE = `# Retainic review algorithm.
#
# 'w' is the word's current progress:
#   w.times_word           correct "Word" recalls so far
#   w.times_translation    correct "Translation" recalls so far
#   w.times_pronunciation  correct "Audio" recalls so far
#   w.has_audio            True if the word is spoken (has a recording, or
#                          the list has text-to-speech on)
#
# Return a Review giving the number of days until each method is due again
# (-1 means that method is finished). The word is fully memorized once
# times_word + times_translation + times_pronunciation reaches mastered_total.

def review(w):
    WORD          = [0, 1, 1, 2, 3, 4, 6, 9]
    TRANSLATION   = [0, 1, 1, 1, 2, 2, 3, 4, 5, 10]
    PRONUNCIATION = [0, 1, 2, 3, 4, 6, 8]

    def gap(table, n):
        return table[n] if n < len(table) else -1

    # All Word + Translation steps (+ Audio steps when the word is spoken).
    mastered_total = len(WORD) + len(TRANSLATION) + (len(PRONUNCIATION) if w.has_audio else 0)

    return Review(
        word          = gap(WORD,          w.times_word),
        translation   = gap(TRANSLATION,   w.times_translation),
        pronunciation = gap(PRONUNCIATION, w.times_pronunciation),
        mastered_total = mastered_total,
    )
`;

// Python preamble: the Review struct the user returns, a word wrapper exposing
// attribute access, and a runner that hands back a plain list of numbers so no
// Python objects need to survive the boundary.
const PREAMBLE = `
class Review:
    def __init__(self, word=-1, translation=-1, pronunciation=-1, mastered_total=0):
        self.word = word
        self.translation = translation
        self.pronunciation = pronunciation
        self.mastered_total = mastered_total

class _Word:
    def __init__(self, tw, tt, tp, ha):
        self.times_word = tw
        self.times_translation = tt
        self.times_pronunciation = tp
        self.has_audio = ha

def _make_runner(fn):
    def run(tw, tt, tp, ha):
        r = fn(_Word(tw, tt, tp, bool(ha)))
        return [float(r.word), float(r.translation), float(r.pronunciation), float(r.mastered_total)]
    return run
`;

/** The default glossary algorithm, shown pre-filled in the editor. Mirrors the
 *  built-in schedule exactly, so saving it unchanged behaves like no override. */
export const DEFAULT_GLOSSARY_ALGORITHM_CODE = `# Retainic glossary review algorithm.
#
# 'e' is the progress of the side being scheduled:
#   e.times_term        correct recalls of the term so far
#   e.times_definition  correct recalls of this definition so far
#
# A term is shown one card per meaning: each definition is scheduled on its own,
# and 'e.times_definition' is the count for whichever one is being scheduled.
#
# Return a GlossaryReview giving the number of days until each side is due again
# (-1 means that side is finished). A term is memorized once the term side and
# every one of its definitions are finished.

def review(e):
    GAPS = [0, 1, 2, 4, 7]

    def gap(n):
        return GAPS[n] if n < len(GAPS) else -1

    return GlossaryReview(
        term       = gap(e.times_term),
        definition = gap(e.times_definition),
    )
`;

// The glossary counterpart of PREAMBLE: two sides instead of three methods, and
// no mastery total — a side is finished when its own schedule runs out.
const GLOSSARY_PREAMBLE = `
class GlossaryReview:
    def __init__(self, term=-1, definition=-1):
        self.term = term
        self.definition = definition

class _Entry:
    def __init__(self, tt, td):
        self.times_term = tt
        self.times_definition = td

def _make_glossary_runner(fn):
    def run(tt, td):
        r = fn(_Entry(tt, td))
        return [float(r.term), float(r.definition)]
    return run
`;

// Runs once, right after Pyodide loads, before any user code. It severs
// Pyodide's bridge to the page's JavaScript: the `js` module (window, fetch,
// document.cookie, IndexedDB — where the Firebase auth token is stored) and the
// `pyodide` module (whose `run_js` executes arbitrary JavaScript). A review
// algorithm is meant to be pure arithmetic and needs neither, so a custom
// snippet can no longer reach Firebase or the network from inside Pyodide.
//
// This is defense-in-depth, not the only safeguard: Python introspection makes a
// single-interpreter sandbox impossible to fully guarantee, so we also never run
// another user's algorithm (see fetchSharedList) — the code compiled here is
// always the current user's own, executed in their own session.
const SANDBOX = `
def _retainic_lock():
    import sys
    # Drop Pyodide's importer for \`import js\` so it can't be re-resolved, then
    # poison the cached bridge modules so importing them raises ImportError.
    sys.meta_path = [f for f in sys.meta_path if type(f).__name__ != "JsFinder"]
    for name in list(sys.modules):
        if name.split(".")[0] in ("js", "pyodide"):
            sys.modules[name] = None
_retainic_lock()
del _retainic_lock
`;

/** First-layer guard with a clear message: a review algorithm is pure
 *  arithmetic, so reject any attempt to reach the JavaScript bridge or dynamic
 *  imports up front. The runtime lockdown in `pyodide()` is the actual
 *  enforcement (this denylist alone could be evaded), but this turns the common
 *  case into a friendly error instead of a raw Python ImportError. */
function guardSource(code) {
  if (/\b(?:import\s+js\b|from\s+js\b|pyodide|run_js|__import__|importlib|eval\s*\(|exec\s*\()/.test(code)) {
    throw new Error("For security, review algorithms may only use plain Python arithmetic — no 'js'/'pyodide' access, imports, or eval/exec.");
  }
}

let pyodidePromise = null;

/** Loads Pyodide once (idempotent), then locks it down before any user code. */
function pyodide() {
  if (!pyodidePromise) {
    pyodidePromise = import(PYODIDE_URL)
      .then((m) => m.loadPyodide())
      .then((py) => { py.runPython(SANDBOX); return py; });
  }
  return pyodidePromise;
}

/** Compiles Python source into a synchronous review function
 *    state -> { word, translation, pronunciation, masteredTotal }
 *  Rejects if the code can't be loaded or doesn't define a usable `review`. */
export async function compileAlgorithm(code) {
  guardSource(code);
  const py = await pyodide();
  py.runPython(PREAMBLE);
  py.runPython(code);
  // Capture the function this snippet just defined. A later compile rebinds the
  // global `review`, so the runner has to close over the one it was made with.
  const runner = py.runPython("_make_runner(review)");

  // Actually run review() across a spread of word states — low and high counts,
  // with and without audio — so a runtime error (e.g. an index out of range for
  // a well-practised word) or a bad return value surfaces now, at check-in,
  // rather than mid-practice. Each result must be four finite numbers.
  const probes = [];
  for (const n of [0, 1, 2, 5, 20, 100]) { probes.push([n, n, n, true]); probes.push([n, n, n, false]); }
  probes.push([3, 7, 2, true], [0, 10, 0, false], [8, 10, 7, true]);
  for (const [tw, tt, tp, ha] of probes) {
    let proxy;
    try {
      proxy = runner(tw, tt, tp, ha);
      const arr = proxy.toJs();
      if (!Array.isArray(arr) || arr.length !== 4 || arr.some((v) => typeof v !== "number" || !Number.isFinite(v))) {
        throw new Error("review() must return Review(word, translation, pronunciation, mastered_total) with numeric values.");
      }
    } finally {
      if (proxy) proxy.destroy();
    }
  }

  const cache = new Map();
  return (state) => {
    const key = `${state.times_word}|${state.times_translation}|${state.times_pronunciation}|${state.has_audio ? 1 : 0}`;
    const hit = cache.get(key);
    if (hit) return hit;
    const proxy = runner(state.times_word, state.times_translation, state.times_pronunciation, state.has_audio);
    const arr = proxy.toJs();
    proxy.destroy();
    const out = { word: arr[0], translation: arr[1], pronunciation: arr[2], masteredTotal: arr[3] };
    cache.set(key, out);
    return out;
  };
}

/** Compiles Python source into a synchronous glossary review function
 *    state -> { term, definition }
 *  Rejects if the code can't be loaded or doesn't define a usable `review`. */
export async function compileGlossaryAlgorithm(code) {
  guardSource(code);
  const py = await pyodide();
  py.runPython(GLOSSARY_PREAMBLE);
  py.runPython(code);
  const runner = py.runPython("_make_glossary_runner(review)");

  // Run review() across a spread of states — a fresh term, a well-practised
  // one, a term whose definitions are far apart — so a runtime error or a bad
  // return value surfaces now rather than mid-practice.
  const probes = [[0, 0], [1, 0], [0, 1], [2, 2], [5, 5], [20, 3], [3, 20], [100, 100]];
  for (const [tt, td] of probes) {
    let proxy;
    try {
      proxy = runner(tt, td);
      const arr = proxy.toJs();
      if (!Array.isArray(arr) || arr.length !== 2 || arr.some((v) => typeof v !== "number" || !Number.isFinite(v))) {
        throw new Error("review() must return GlossaryReview(term, definition) with numeric values.");
      }
    } finally {
      if (proxy) proxy.destroy();
    }
  }

  const cache = new Map();
  return (state) => {
    const key = `${state.times_term}|${state.times_definition}`;
    const hit = cache.get(key);
    if (hit) return hit;
    const proxy = runner(state.times_term, state.times_definition);
    const arr = proxy.toJs();
    proxy.destroy();
    const out = { term: arr[0], definition: arr[1] };
    cache.set(key, out);
    return out;
  };
}

// The code string currently installed, so switching between lists doesn't
// recompile the same algorithm. Words and glossaries schedule independently, so
// each remembers its own.
let installedCode = null;
let installedGlossaryCode = null;

/** Installs `code` as the active algorithm. Empty/blank installs the built-in
 *  default (no Pyodide load). Rejects — after falling back to the default — if
 *  the code fails to compile, so the caller can surface the error. */
export async function useAlgorithm(code) {
  const trimmed = (code || "").trim();
  if (!trimmed) { useDefaultAlgorithm(); return; }
  if (trimmed === installedCode) return;
  try {
    const fn = await compileAlgorithm(trimmed);
    installedCode = trimmed;
    setActiveAlgorithm(fn);
  } catch (e) {
    useDefaultAlgorithm();
    throw e;
  }
}

/** Resets word scheduling to the built-in default. */
export function useDefaultAlgorithm() {
  installedCode = null;
  setActiveAlgorithm(null);
}

/** Installs `code` as the active glossary algorithm. Empty/blank installs the
 *  built-in default (no Pyodide load). Rejects — after falling back to the
 *  default — if the code fails to compile, so the caller can surface the error. */
export async function useGlossaryAlgorithm(code) {
  const trimmed = (code || "").trim();
  if (!trimmed) { useDefaultGlossaryAlgorithm(); return; }
  if (trimmed === installedGlossaryCode) return;
  try {
    const fn = await compileGlossaryAlgorithm(trimmed);
    installedGlossaryCode = trimmed;
    setActiveGlossaryAlgorithm(fn);
  } catch (e) {
    useDefaultGlossaryAlgorithm();
    throw e;
  }
}

/** Resets glossary scheduling to the built-in default. */
export function useDefaultGlossaryAlgorithm() {
  installedGlossaryCode = null;
  setActiveGlossaryAlgorithm(null);
}
