import Foundation

/// Orders IP checks: newer checks supersede older ones, and periodic checks are skipped
/// while another check is still running so slow lookups don't pile up.
struct CheckCoordinator {
    enum Trigger {
        /// The periodic timer; skipped while a check is in flight.
        case timer
        /// Launch, network changes and "Check Now"; always start and supersede older checks.
        case immediate
    }

    private(set) var generation = 0
    private(set) var inFlightGeneration: Int?

    var isCheckInFlight: Bool { inFlightGeneration != nil }

    /// Starts a check and returns its generation, or nil when it should be skipped.
    mutating func begin(_ trigger: Trigger) -> Int? {
        if trigger == .timer && isCheckInFlight {
            return nil
        }
        generation += 1
        inFlightGeneration = generation
        return generation
    }

    /// Whether results from `generation` are still the newest and may be applied.
    func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation
    }

    mutating func finish(_ generation: Int) {
        if inFlightGeneration == generation {
            inFlightGeneration = nil
        }
    }
}
