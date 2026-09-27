// Measured, interruptible sheet resizing. The height is animated rather than
// scaling the panel, so text and controls keep their normal size throughout.
export function createSheetMotion(sheet) {
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const fades = new Map();
  let resizeAnimation = null;
  let disposed = false;

  function cancel() {
    resizeAnimation?.cancel();
    resizeAnimation = null;
    for (const animation of fades.values()) animation.cancel();
    fades.clear();
  }

  // If the viewport/keyboard changes or motion is disabled mid-transition,
  // immediately return to natural layout, respecting the sheet's max-height.
  window.addEventListener("resize", cancel);
  reducedMotion.addEventListener("change", cancel);

  return {
    resize(update, { panels = [], animate = true } = {}) {
      if (disposed) return;
      const before = getComputedStyle(sheet);
      // Computed height includes the current WAAPI presentation value but not
      // the open/close transform; a rapid reversal therefore never jumps.
      const from = before.height;
      const duration = parseFloat(before.getPropertyValue("--duration-panel")) || 240;
      const easing = before.getPropertyValue("--ease-drawer").trim() || "cubic-bezier(.32,.72,0,1)";
      const opacities = new Map(panels.map((panel) => {
        const style = getComputedStyle(panel);
        return [panel, style.display === "none" ? 0 : Number(style.opacity)];
      }));
      cancel();
      update();
      if (!animate || reducedMotion.matches || !sheet.isConnected || !sheet.animate) return;

      // No inline height is left behind. When the animation finishes, natural
      // sizing resumes so validation messages and translations can still grow.
      const to = getComputedStyle(sheet).height;
      if (from !== to) {
        const animation = sheet.animate([{ height: from }, { height: to }], { duration, easing });
        resizeAnimation = animation;
        animation.onfinish = () => {
          if (resizeAnimation === animation) resizeAnimation = null;
        };
      }
      for (const panel of panels) {
        const opacity = opacities.get(panel);
        if (opacity >= 1 || getComputedStyle(panel).display === "none") continue;
        const animation = panel.animate([{ opacity }, { opacity: 1 }], { duration: 160, easing });
        fades.set(panel, animation);
        animation.onfinish = () => {
          if (fades.get(panel) === animation) fades.delete(panel);
        };
      }
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      // Keep a closing panel at its current visible size until it is removed.
      if (resizeAnimation) sheet.style.height = getComputedStyle(sheet).height;
      cancel();
      window.removeEventListener("resize", cancel);
      reducedMotion.removeEventListener("change", cancel);
    },
  };
}
