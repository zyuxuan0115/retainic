//
//  ReviewOrdering.swift
//  Retainic
//
//  Lapse-derived weighted ordering for practice sessions. This intentionally
//  uses the aggregate memoryStats already persisted by every client.
//

import Foundation

extension VocabWord {
    func memoryLapses(for aspect: String) -> Int {
        guard let stat = memoryStats?[aspect] else { return 0 }
        return max(0, stat.seen - stat.timesRemembered)
    }

    func reviewWeight(for aspect: String) -> Double {
        Double(1 + min(memoryLapses(for: aspect), 9))
    }
}

/// Weighted random permutation using exponential-race keys. Every item remains
/// in the deck exactly once; higher-weight items merely tend to sort earlier.
func weightedReviewOrder<Item>(
    _ items: [Item],
    weight: (Item) -> Double,
    random: () -> Double = { Double.random(in: 0..<1) }
) -> [Item] {
    var keyed: [(item: Item, index: Int, key: Double)] = []
    keyed.reserveCapacity(items.count)
    for (index, item) in items.enumerated() {
        let boundedWeight = max(1, weight(item))
        let unit = min(1 - Double.ulpOfOne, max(Double.leastNonzeroMagnitude, random()))
        keyed.append((item, index, -log(unit) / boundedWeight))
    }
    keyed.sort { lhs, rhs in
        lhs.key == rhs.key ? lhs.index < rhs.index : lhs.key < rhs.key
    }
    return keyed.map(\.item)
}
