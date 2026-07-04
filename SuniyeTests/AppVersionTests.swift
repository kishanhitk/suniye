import XCTest
@testable import Suniye

final class AppVersionTests: XCTestCase {
    func testSemVerParsesSupportedFormats() {
        XCTAssertEqual(SemVer(rawValue: "0.1"), SemVer(rawValue: "0.1.0"))
        XCTAssertEqual(SemVer(rawValue: "1"), SemVer(rawValue: "1.0.0"))
        XCTAssertEqual(SemVer(rawValue: "v2.3.4"), SemVer(rawValue: "2.3.4"))
    }

    func testSemVerComparison() {
        XCTAssertLessThan(SemVer(rawValue: "0.0.9")!, SemVer(rawValue: "0.1.0")!)
        XCTAssertLessThan(SemVer(rawValue: "1.9.9")!, SemVer(rawValue: "2.0.0")!)
    }

    func testSemVerRejectsInvalidValues() {
        XCTAssertNil(SemVer(rawValue: ""))
        XCTAssertNil(SemVer(rawValue: "1.2.3.4"))
        XCTAssertNil(SemVer(rawValue: "1.a.0"))
    }

    func testDisplayStringMarksTipBuilds() {
        let version = AppVersion(marketing: SemVer(rawValue: "1.2.3")!, build: 456, channel: .tip)

        XCTAssertEqual(version.displayString, "v1.2.3 (456) Tip")
    }

    func testBundleMetadataLoadsTipChannel() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeAppVersionTests-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "dev.suniye.tests.bundle.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
            "SuniyeBuildChannel": "tip"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))

        let version = try XCTUnwrap(Bundle(url: bundleURL).flatMap(AppVersion.fromBundle))

        XCTAssertEqual(version.displayString, "v1.2.3 (456) Tip")
    }

    func testAppIdentityLoadsPreviewDisplayNameFromBundle() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeAppIdentityTests-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "dev.suniye.app.preview",
            "CFBundlePackageType": "BNDL",
            "CFBundleDisplayName": "Suniye Preview"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))

        let identity = AppIdentity.fromBundle(try XCTUnwrap(Bundle(url: bundleURL)))

        XCTAssertEqual(identity.displayName, "Suniye Preview")
        XCTAssertTrue(identity.isPreview)
    }
}
