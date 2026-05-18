import Foundation

/// Vector clock for conflict detection in sync operations.
public struct VectorClock: Codable, Equatable, Sendable {
    var counters: [String: Int] = [:]

    init() {}

    mutating func increment(machineId: String) {
        counters[machineId, default: 0] += 1
    }

    func happenedBefore(_ other: VectorClock) -> Bool {
        var allKeys = Set(counters.keys).union(other.counters.keys)
        return allKeys.allSatisfy { key in
            (counters[key] ?? 0) <= (other.counters[key] ?? 0)
        } && counters != other.counters
    }

    func isConcurrent(with other: VectorClock) -> Bool {
        !happenedBefore(other) && !other.happenedBefore(self) && self != other
    }
}
