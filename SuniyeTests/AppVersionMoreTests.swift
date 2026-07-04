import XCTest
@testable import Suniye

final class AppVersionMoreTests: XCTestCase {
    func testSemVerRejectsNonNumericAndNegativeMajor() {
        XCTAssertNil(SemVer(rawValue: "abc"))
        XCTAssertNil(SemVer(rawValue: "-1.2.3"))
    }

    func testFromBundleReturnsNilWithoutMarketingVersion() throws {
        let bundle = try makeBundle(info: [
            "CFBundleIdentifier": "dev.suniye.tests.more.bundle.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "456",
        ])

        XCTAssertNil(AppVersion.fromBundle(bundle))
    }

    func testFromBundleReturnsNilForUnparseableMarketingVersion() throws {
        let bundle = try makeBundle(info: [
            "CFBundleIdentifier": "dev.suniye.tests.more.bundle.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "not-a-version",
        ])

        XCTAssertNil(AppVersion.fromBundle(bundle))
    }

    private func makeBundle(info: [String: Any]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeAppVersionMoreTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }

        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}
