import XCTest
import ServiceManagement

private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}

final class LaunchAtLoginTests: XCTestCase {

    private struct TestError: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    func testStateReflectsServiceStatus() {
        XCTAssertFalse(LaunchAtLogin(service: FakeLoginItemService(status: .notRegistered)).isEnabled)
        XCTAssertFalse(LaunchAtLogin(service: FakeLoginItemService(status: .notFound)).isEnabled)
        XCTAssertTrue(LaunchAtLogin(service: FakeLoginItemService(status: .enabled)).isEnabled)
    }

    func testRequiresApprovalCountsAsEnabled() {
        let launchAtLogin = LaunchAtLogin(service: FakeLoginItemService(status: .requiresApproval))
        XCTAssertTrue(launchAtLogin.isEnabled)
        XCTAssertTrue(launchAtLogin.requiresApproval)
    }

    func testEnableRegisters() {
        let service = FakeLoginItemService(status: .notRegistered)
        XCTAssertNil(LaunchAtLogin(service: service).setEnabled(true))
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.status, .enabled)
    }

    func testDisableUnregisters() {
        let service = FakeLoginItemService(status: .enabled)
        XCTAssertNil(LaunchAtLogin(service: service).setEnabled(false))
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(service.status, .notRegistered)
    }

    func testNoOpWhenAlreadyInRequestedState() {
        let service = FakeLoginItemService(status: .enabled)
        XCTAssertNil(LaunchAtLogin(service: service).setEnabled(true))
        XCTAssertEqual(service.registerCalls, 0)
    }

    func testRegisterFailureReturnsMessageAndKeepsState() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = TestError()
        let launchAtLogin = LaunchAtLogin(service: service)
        XCTAssertEqual(launchAtLogin.setEnabled(true), "Couldn't turn on launch at login: Operation not permitted")
        XCTAssertFalse(launchAtLogin.isEnabled)
    }

    func testUnregisterFailureReturnsMessage() {
        let service = FakeLoginItemService(status: .enabled)
        service.unregisterError = TestError()
        let launchAtLogin = LaunchAtLogin(service: service)
        XCTAssertEqual(launchAtLogin.setEnabled(false), "Couldn't turn off launch at login: Operation not permitted")
        XCTAssertTrue(launchAtLogin.isEnabled)
    }
}
