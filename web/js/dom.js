//
//  dom.js
//  Retainic Web
//
//  Tiny DOM helpers so the views read declaratively without a framework.
//

/** el("div.card", { onclick }, child, child, …) → HTMLElement.
 *  The tag string may include .class and #id shorthands. */
export function el(tag, props = {}, ...children) {
  let tagName = "div";
  const classes = [];
  let id = null;
  const m = tag.match(/^([a-zA-Z0-9]+)?([.#][\w-]+)*$/);
  tagName = (tag.match(/^[a-zA-Z0-9]+/) || ["div"])[0];
  for (const part of tag.match(/[.#][\w-]+/g) || []) {
    if (part[0] === ".") classes.push(part.slice(1));
    else id = part.slice(1);
  }
  const node = document.createElement(tagName);
  if (id) node.id = id;
  if (classes.length) node.className = classes.join(" ");
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === "class") node.className += (node.className ? " " : "") + v;
    else if (k === "html") node.innerHTML = v;
    else if (k.startsWith("on") && typeof v === "function") node.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === "value") node.value = v;
    else if (k === "checked" || k === "disabled" || k === "selected") node[k] = !!v;
    else node.setAttribute(k, v);
  }
  appendAll(node, children);
  return node;
}

function appendAll(node, children) {
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    node.appendChild(typeof c === "string" || typeof c === "number" ? document.createTextNode(String(c)) : c);
  }
}

export function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
  return node;
}

/** Saves a blob to the user's downloads as `filename`. Shared by the list and
 *  glossary CSV exports. */
export function triggerDownload(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = el("a", { href: url, download: filename });
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Namespaced element creation for inline SVG charts. */
export function svgEl(tag, attrs = {}, ...children) {
  const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const c of children.flat()) if (c != null) node.appendChild(c);
  return node;
}

/** Asks the browser to confirm before the page is left, so a half-written
 *  import isn't abandoned by a stray reload. Only installed while `setBusy`
 *  says a write is running. */
function warnBeforeUnload(e) {
  e.preventDefault();
  e.returnValue = "";
}

/** Takes the app behind the overlay out of play while a write runs. The overlay
 *  already swallows clicks; this also keeps the keyboard from tabbing into it. */
function setAppInert(value) {
  const app = document.getElementById("app");
  if (app) app.inert = value;
}

/** A simple modal sheet. Returns { close }. `variant` adds a class to the
 *  overlay (e.g. "alert" for a compact centered confirm dialog). */
export function presentSheet(contentBuilder, { variant = "" } = {}) {
  const overlay = el(".sheet-overlay" + (variant ? "." + variant : ""));
  const sheet = el(".sheet");
  let dismissible = true;
  const api = {
    close() {
      // A sheet that closes straight after its write finishes never clears the
      // busy state itself, so undo the page-wide part of it here too.
      window.removeEventListener("beforeunload", warnBeforeUnload);
      setAppInert(false);
      overlay.classList.add("closing");
      setTimeout(() => overlay.remove(), 180);
    },
    // Toggle whether a click outside the sheet dismisses it (e.g. disabled while
    // a non-interruptible operation runs). `close()` still works programmatically.
    setDismissible(value) { dismissible = value; },
    // Locks the panel for an uninterruptible write, such as importing a large
    // file: nothing inside it can be clicked, focused or typed into, a click
    // outside won't close it, and leaving the page asks for confirmation first.
    // Everything behind the sheet is already covered by the overlay.
    setBusy(busy) {
      dismissible = !busy;
      sheet.inert = busy;
      sheet.classList.toggle("busy", busy);
      setAppInert(busy);
      if (busy) window.addEventListener("beforeunload", warnBeforeUnload);
      else window.removeEventListener("beforeunload", warnBeforeUnload);
    },
  };
  overlay.addEventListener("click", (e) => { if (e.target === overlay && dismissible) api.close(); });
  sheet.appendChild(contentBuilder(api));
  overlay.appendChild(sheet);
  document.body.appendChild(overlay);
  requestAnimationFrame(() => overlay.classList.add("open"));
  return api;
}

export function toast(message) {
  const node = el(".toast", {}, message);
  document.body.appendChild(node);
  requestAnimationFrame(() => node.classList.add("show"));
  setTimeout(() => { node.classList.remove("show"); setTimeout(() => node.remove(), 300); }, 2600);
}
