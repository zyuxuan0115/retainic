package com.retainic.app.ui

import com.retainic.app.data.VocabWord
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/** Incorrect recalls already persisted for one aspect. */
internal fun VocabWord.memoryLapses(aspect: String): Int {
    val stat = memoryStats?.get(aspect) ?: return 0
    return max(0, stat.seen - stat.timesRemembered)
}

/** Bounded priority multiplier: 1 for unseen/perfect items, up to 10. */
internal fun VocabWord.reviewWeight(aspect: String): Double =
    (1 + min(memoryLapses(aspect), 9)).toDouble()

/** Weighted random permutation using exponential-race keys. */
internal fun <Item> weightedReviewOrder(
    items: List<Item>,
    weight: (Item) -> Double,
    random: () -> Double = { Random.nextDouble() },
): List<Item> = items.mapIndexed { index, item ->
    val boundedWeight = max(1.0, weight(item))
    val unit = random().coerceIn(Double.MIN_VALUE, 1.0 - Math.ulp(1.0))
    Triple(item, index, -ln(unit) / boundedWeight)
}.sortedWith(compareBy<Triple<Item, Int, Double>> { it.third }.thenBy { it.second })
    .map { it.first }
