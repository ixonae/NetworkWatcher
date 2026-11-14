import XCTest

final class CheckCoordinatorTests: XCTestCase {

    func testFirstCheckStarts() {
        var coordinator = CheckCoordinator()
        XCTAssertEqual(coordinator.begin(.timer), 1)
        XCTAssertTrue(coordinator.isCheckInFlight)
    }

    func testTimerCheckSkippedWhileInFlight() {
        var coordinator = CheckCoordinator()
        _ = coordinator.begin(.immediate)
        XCTAssertNil(coordinator.begin(.timer))
        XCTAssertEqual(coordinator.generation, 1)
    }

    func testTimerCheckStartsAfterFinish() {
        var coordinator = CheckCoordinator()
        let first = coordinator.begin(.timer)!
        coordinator.finish(first)
        XCTAssertFalse(coordinator.isCheckInFlight)
        XCTAssertEqual(coordinator.begin(.timer), 2)
    }

    func testImmediateCheckSupersedesInFlightCheck() {
        var coordinator = CheckCoordinator()
        let old = coordinator.begin(.timer)!
        let new = coordinator.begin(.immediate)!
        XCTAssertFalse(coordinator.isCurrent(old))
        XCTAssertTrue(coordinator.isCurrent(new))
    }

    func testFinishingSupersededCheckKeepsNewerInFlight() {
        var coordinator = CheckCoordinator()
        let old = coordinator.begin(.timer)!
        let new = coordinator.begin(.immediate)!
        coordinator.finish(old)
        XCTAssertTrue(coordinator.isCheckInFlight)
        XCTAssertNil(coordinator.begin(.timer))
        coordinator.finish(new)
        XCTAssertFalse(coordinator.isCheckInFlight)
    }

    func testFinishIsIdempotent() {
        var coordinator = CheckCoordinator()
        let generation = coordinator.begin(.immediate)!
        coordinator.finish(generation)
        coordinator.finish(generation)
        XCTAssertFalse(coordinator.isCheckInFlight)
        XCTAssertTrue(coordinator.isCurrent(generation))
    }
}
