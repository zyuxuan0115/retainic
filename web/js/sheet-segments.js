import { el } from "./dom.js";

/** Shared sliding selection for creation sheets, regardless of mode count. */
export function sheetSegments(options, initial, onChange) {
  const indicator = el(".segment-indicator", { "aria-hidden": "true" });
  let current = initial;
  const buttons = options.map(({ id, label }) => el("button.seg" + (id === initial ? ".active" : ""), {
    type: "button", "aria-pressed": String(id === initial),
    onclick: (event) => {
      if (current === id) return;
      current = id;
      const animate = event.detail !== 0;
      indicator.style.transition = animate ? "" : "none";
      indicator.style.transform = `translateX(${options.findIndex((option) => option.id === id) * 100}%)`;
      buttons.forEach((button, index) => {
        const active = options[index].id === id;
        button.classList.toggle("active", active);
        button.setAttribute("aria-pressed", String(active));
      });
      onChange(id, animate);
    },
  }, label));
  indicator.style.transform = `translateX(${options.findIndex((option) => option.id === initial) * 100}%)`;
  return el(".segmented.sheet-segments", { style: `--segment-count:${options.length}` }, indicator, ...buttons);
}
