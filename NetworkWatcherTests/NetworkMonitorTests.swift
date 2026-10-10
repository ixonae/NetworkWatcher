import XCTest
import Cocoa

/// Captures debounced work items so tests control when they run instead of waiting on the clock.
private final class ManualScheduler {
    private(set) var delays: [TimeInterval] = []
    private var items: [DispatchWorkItem] = []

    var pendingCount: Int { items.filter { !$0.isCancelled }.count }

    func schedule(_ delay: TimeInterval, _ work: DispatchWorkItem) {
        delays.append(delay)
        items.append(work)
    }

    func fireAll() {
        let due = items
        items.removeAll()
        for work in due where !work.isCancelled {
            work.perform()
        }
    }
}

final class NetworkMonitorTests: XCTestCase {

    private let debounce: TimeInterval = 0.05
    private var scheduler: ManualScheduler!
    private var monitor: NetworkMonitor!
    private var callCount = 0

    override func setUp() {
        super.setUp()
        scheduler = ManualScheduler()
        monitor = NetworkMonitor(debounceInterval: debounce, scheduler: scheduler.schedule)
        callCount = 0
        monitor.onNetworkChange = { [unowned self] in self.callCount += 1 }
        monitor.startMonitoring()
    }

    override func tearDown() {
        monitor.stopMonitoring()
        monitor = nil
        scheduler = nil
        super.tearDown()
    }

    /// CoreWLAN delegate methods hop to the main queue; let that hop run.
    private func drainMainQueue() {
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    private func postWake() {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: - Configuration

    func testDefaultDebounceInterval() {
        XCTAssertEqual(NetworkMonitor().debounceInterval, 2)
    }

    func testCustomDebounceInterval() {
        XCTAssertEqual(monitor.debounceInterval, debounce)
    }

    func testWorkIsScheduledWithDebounceInterval() {
        monitor.scheduleChangeNotification()
        XCTAssertEqual(scheduler.delays, [debounce])
    }

    // MARK: - Debouncing

    func testChangeFiresCallbackOnce() {
        monitor.scheduleChangeNotification()
        scheduler.fireAll()
        XCTAssertEqual(callCount, 1)
    }

    func testCallbackNotFiredBeforeDebounceElapses() {
        monitor.scheduleChangeNotification()
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    func testBurstOfChangesIsCoalesced() {
        for _ in 0..<5 { monitor.scheduleChangeNotification() }
        XCTAssertEqual(scheduler.pendingCount, 1)

        scheduler.fireAll()
        XCTAssertEqual(callCount, 1)
    }

    func testSeparatedChangesFireSeparately() {
        monitor.scheduleChangeNotification()
        scheduler.fireAll()
        monitor.scheduleChangeNotification()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 2)
    }

    func testNoCallbackSetDoesNotCrash() {
        monitor.onNetworkChange = nil
        monitor.scheduleChangeNotification()
        scheduler.fireAll()
    }

    func testChangeIgnoredWhenNotMonitoring() {
        monitor.stopMonitoring()
        monitor.scheduleChangeNotification()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 0)
    }

    // MARK: - CoreWLAN delegate events

    func testSSIDChangeTriggersCallback() {
        monitor.ssidDidChangeForWiFiInterface(withName: "en0")
        drainMainQueue()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 1)
    }

    func testBSSIDChangeTriggersCallback() {
        monitor.bssidDidChangeForWiFiInterface(withName: "en0")
        drainMainQueue()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 1)
    }

    func testSSIDAndBSSIDChangesCoalesce() {
        monitor.ssidDidChangeForWiFiInterface(withName: "en0")
        monitor.bssidDidChangeForWiFiInterface(withName: "en0")
        drainMainQueue()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 1)
    }

    func testWiFiEventQueuedBeforeStopDoesNotFire() {
        monitor.ssidDidChangeForWiFiInterface(withName: "en0")
        monitor.stopMonitoring()
        drainMainQueue()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Wake from sleep

    func testWakeNotificationTriggersCallbackWhenMonitoring() {
        postWake()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 1)
    }

    func testWakeNotificationIgnoredBeforeMonitoringStarts() {
        let idle = NetworkMonitor(debounceInterval: debounce, scheduler: scheduler.schedule)
        var fired = false
        idle.onNetworkChange = { fired = true }

        postWake()
        scheduler.fireAll()

        XCTAssertFalse(fired)
    }

    // MARK: - Dynamic store

    func testStartMonitoringRegistersDynamicStore() {
        XCTAssertNotNil(monitor.dynamicStore)
    }

    func testStopMonitoringReleasesDynamicStore() {
        monitor.stopMonitoring()
        XCTAssertNil(monitor.dynamicStore)
    }

    func testDynamicStoreWatchesGlobalAddressKeys() {
        XCTAssertEqual(
            Set(NetworkMonitor.dynamicStoreKeys),
            ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"]
        )
    }

    func testDynamicStorePatternMatchesOnlyPhysicalLinks() throws {
        let regexes = try NetworkMonitor.dynamicStorePatterns.map { try NSRegularExpression(pattern: "^\($0)$") }
        func matches(_ key: String) -> Bool {
            regexes.contains { $0.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil }
        }

        XCTAssertTrue(matches("State:/Network/Interface/en0/Link"))
        XCTAssertTrue(matches("State:/Network/Interface/en12/Link"))
        XCTAssertFalse(matches("State:/Network/Interface/awdl0/Link"))
        XCTAssertFalse(matches("State:/Network/Interface/llw0/Link"))
        XCTAssertFalse(matches("State:/Network/Interface/utun3/Link"))
        XCTAssertFalse(matches("State:/Network/Interface/en0/IPv4"))
    }

    // MARK: - Start / stop

    func testStartMonitoringTwiceDoesNotDuplicateWakeEvents() {
        monitor.startMonitoring()

        postWake()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 1)
    }

    func testStopMonitoringStopsWakeEvents() {
        monitor.stopMonitoring()

        postWake()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 0)
    }

    func testStopMonitoringCancelsPendingNotification() {
        monitor.scheduleChangeNotification()
        monitor.stopMonitoring()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 0)
    }

    func testStopMonitoringWithoutStartIsSafe() {
        let idle = NetworkMonitor(debounceInterval: debounce, scheduler: scheduler.schedule)
        idle.stopMonitoring()
    }

    func testMonitoringCanBeRestarted() {
        monitor.stopMonitoring()
        monitor.startMonitoring()

        postWake()
        scheduler.fireAll()

        XCTAssertEqual(callCount, 1)
    }

    func testMonitorDeallocatesWhileMonitoring() {
        weak var weakMonitor: NetworkMonitor?
        autoreleasepool {
            let local = NetworkMonitor(debounceInterval: debounce, scheduler: scheduler.schedule)
            local.startMonitoring()
            weakMonitor = local
        }
        XCTAssertNil(weakMonitor)
    }
}
