import Foundation
import XCTest
@testable import AlcoveCore

final class FileIdentityTests: XCTestCase {
    func testIdentityUsesAStandardizedPathValue() {
        let identity = FileIdentity(url: URL(fileURLWithPath: "/tmp/portal/../portal/item"))

        XCTAssertEqual(identity.path, "/tmp/portal/item")
    }

    func testFileItemUsesStandardizedURLAndDoesNotRequireFilesystemMetadata() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/path/that/does/not/exist/../item"),
            name: "Item",
            isDirectory: true,
            isHidden: false
        )

        XCTAssertEqual(item.url.path, "/path/that/does/not/item")
        XCTAssertEqual(item.id.path, item.url.path)
        XCTAssertEqual(item.name, "Item")
        XCTAssertTrue(item.isDirectory)
        XCTAssertFalse(item.isHidden)
    }
}
