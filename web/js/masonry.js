//
//  masonry.js
//  Retainic Web
//
//  Column packing for card lists. Every card keeps the column width, its
//  height follows its own text, and each one drops into the shortest column so
//  the layout closes up instead of leaving a gap under the short cards.
//
//  Only wide screens get this: that's where styles.css turns a .list into a
//  card grid. The cards are positioned absolutely, so the .masonry class that
//  switches the CSS over is added here — if this never runs, the list keeps
//  its plain grid.
//

/** Lays the cards out, and keeps them laid out as the list is resized.
 *  Returns { update, dispose }: call update() after refilling the host,
 *  dispose() before dropping it. */
export function masonry(host) {
  let lastWidth = null;
  const update = () => { lastWidth = host.clientWidth; layout(host); };

  update();
  // Text measured before the fonts land wraps differently once they arrive.
  document.fonts?.ready?.then(() => { if (host.isConnected) update(); });

  const observer = new ResizeObserver(() => {
    if (!host.isConnected) return;
    // Laying out sets the host's height, which would call us straight back.
    // Only a width change can move a card.
    if (host.clientWidth !== lastWidth) update();
  });
  observer.observe(host);
  return { update, dispose: () => observer.disconnect() };
}

function layout(host) {
  const cards = Array.from(host.children);
  const style = getComputedStyle(host);
  const gap = parseFloat(style.getPropertyValue("--card-gap"));
  const minimum = parseFloat(style.getPropertyValue("--card-min"));
  // The narrow layout is a plain stacked list, and an empty list has nothing
  // to place; either way the cards lay themselves out.
  if (!cards.length || !gap || !minimum) return reset(host, cards);

  host.classList.add("masonry");
  const width = host.clientWidth;
  const columns = Math.max(1, Math.floor((width + gap) / (minimum + gap)));
  const cardWidth = (width - gap * (columns - 1)) / columns;
  const bottoms = new Array(columns).fill(0);
  for (const card of cards) {
    const column = bottoms.indexOf(Math.min(...bottoms));
    card.style.width = `${cardWidth}px`;
    card.style.left = `${column * (cardWidth + gap)}px`;
    card.style.top = `${bottoms[column]}px`;
    // Read the height only after the width is in place, so the text has
    // already rewrapped to the column.
    bottoms[column] += card.offsetHeight + gap;
  }
  host.style.height = `${Math.max(...bottoms) - gap}px`;
}

function reset(host, cards) {
  host.classList.remove("masonry");
  host.style.height = "";
  for (const card of cards) card.style.width = card.style.left = card.style.top = "";
}
