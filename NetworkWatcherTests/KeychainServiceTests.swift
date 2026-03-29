import XCTest
@testable import Network_Watcher

final class KeychainServiceTests: XCTestCase {

    private let testKey = "testKey_NetworkWatcherTests"

    override func tearDown() {
        KeychainService.delete(key: testKey)
        super.tearDown()
    }

    func testSaveAndLoad() {
        let saved = KeychainService.save(key: testKey, value: "mySecretToken")
        XCTAssertTrue(saved)

        let loaded = KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, "mySecretToken")
    }

    func testLoadNonExistent() {
        let loaded = KeychainService.load(key: "nonExistentKey_xyz")
        XCTAssertNil(loaded)
    }

    func testOverwrite() {
        KeychainService.save(key: testKey, value: "first")
        KeychainService.save(key: testKey, value: "second")

        let loaded = KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, "second")
    }

    func testDelete() {
        KeychainService.save(key: testKey, value: "toDelete")
        let deleted = KeychainService.delete(key: testKey)
        XCTAssertTrue(deleted)

        let loaded = KeychainService.load(key: testKey)
        XCTAssertNil(loaded)
    }

    func testDeleteNonExistent() {
        let deleted = KeychainService.delete(key: "nonExistentKey_xyz")
        XCTAssertTrue(deleted) // Should return true (errSecItemNotFound is acceptable)
    }

    func testSaveEmptyString() {
        let saved = KeychainService.save(key: testKey, value: "")
        XCTAssertTrue(saved)

        let loaded = KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, "")
    }

    func testSaveUnicodeToken() {
        let token = "tökën-with-spëcial-chars-🔑"
        KeychainService.save(key: testKey, value: token)

        let loaded = KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, token)
    }
}
