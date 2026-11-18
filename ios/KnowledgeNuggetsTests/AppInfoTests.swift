import XCTest
@testable import KnowledgeNuggets

final class AppInfoTests: XCTestCase {
    func testReadsStampedBuild() throws {
        let info = AppInfo(info: [
            "CFBundleShortVersionString": "1.0",
            "KNBuildCommit": "05c395f",
            "KNBuildDate": "2026-11-18T21:55:00Z",
        ])
        XCTAssertEqual(info.versionText, "1.0 (05c395f)")
        let text = try XCTUnwrap(info.builtText(timeZone: TimeZone(identifier: "America/Chicago")!))
        XCTAssertTrue(text.contains("2026"), text)
        XCTAssertTrue(text.contains("3:55"), text)
    }

    func testUnstampedBuildShowsJustTheVersion() {
        let info = AppInfo(info: ["CFBundleShortVersionString": "1.0"])
        XCTAssertEqual(info.versionText, "1.0")
        XCTAssertNil(info.builtText())
    }

    func testTheRunningAppIsStamped() {
        XCTAssertNotNil(AppInfo.current.commit, "The build script should add KNBuildCommit")
        XCTAssertNotNil(AppInfo.current.builtAt, "The build script should add KNBuildDate")
    }
}
