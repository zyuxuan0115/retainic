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

/** Namespaced element creation for inline SVG charts. */
export function svgEl(tag, attrs = {}, ...children) {
  const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const c of children.flat()) if (c != null) node.appendChild(c);
  return node;
}

/** A simple modal sheet. Returns { close }. */
export function presentSheet(contentBuilder) {
  const overlay = el(".sheet-overlay");
  const sheet = el(".sheet");
  const api = {
    close() {
      overlay.classList.add("closing");
      setTimeout(() => overlay.remove(), 180);
    },
  };
  overlay.addEventListener("click", (e) => { if (e.target === overlay) api.close(); });
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
