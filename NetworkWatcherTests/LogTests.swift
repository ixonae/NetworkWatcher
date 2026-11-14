import XCTest

final class LogTests: XCTestCase {
    func testSubsystemFallsBackToAppIdentifier() {
        XCTAssertFalse(Log.subsystem.isEmpty)
        XCTAssertEqual(Log.subsystem, Bundle.main.bundleIdentifier ?? "com.ixonae.NetworkWatcher")
    }

    func testLoggersAreUsable() {
        // Smoke test: logging with private and public values must not crash.
        Log.network.debug("test \(TestIP.stub, privacy: .private)")
        Log.alerts.debug("test \("id", privacy: .public)")
        Log.settings.debug("test")
    }
}
