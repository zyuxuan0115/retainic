//
//  review-order.js
//  Retainic Web
//
//  Per-aspect forgetting priority shared by flashcard deck construction and
//  tests. It derives lapses from the aggregate memoryStats already in Firestore;
//  no new persisted fields are required.
//

/** Incorrect recalls already recorded for one aspect. */
export function memoryLapses(word, aspect) {
  const stat = word?.memoryStats?.[aspect];
  const seen = Number.isFinite(Number(stat?.seen)) ? Number(stat.seen) : 0;
  const remembered = Number.isFinite(Number(stat?.timesRemembered)) ? Number(stat.timesRemembered) : 0;
  return Math.max(0, seen - remembered);
}

/** A bounded priority multiplier: 1 for unseen/perfect items, up to 10. */
export function reviewWeight(word, aspect) {
  return 1 + Math.min(memoryLapses(word, aspect), 9);
}

/**
 * Weighted random permutation using exponential-race keys. Larger weights tend
 * to sort earlier, but every item appears exactly once and ties stay stable.
 * `random` is injectable so the behavior can be regression-tested.
 */
export function weightedOrder(items, weightFor, random = Math.random) {
  return items
    .map((item, index) => {
      const rawWeight = Number(weightFor(item));
      const weight = Number.isFinite(rawWeight) && rawWeight > 0 ? rawWeight : 1;
      const sample = Number(random());
      const unit = Number.isFinite(sample)
        ? Math.min(1 - Number.EPSILON, Math.max(Number.MIN_VALUE, sample))
        : 0.5;
      return { item, index, key: -Math.log(unit) / weight };
    })
    .sort((a, b) => a.key - b.key || a.index - b.index)
    .map(({ item }) => item);
}
