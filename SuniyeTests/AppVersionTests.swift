import XCTest
@testable import Suniye

final class AppVersionTests: XCTestCase {
    func testSemVerParsesSupportedFormats() {
        XCTAssertEqual(SemVer(rawValue: "0.1"), SemVer(rawValue: "0.1.0"))
        XCTAssertEqual(SemVer(rawValue: "1"), SemVer(rawValue: "1.0.0"))
        XCTAssertEqual(SemVer(rawValue: "v2.3.4"), SemVer(rawValue: "2.3.4"))
    }

    func testSemVerOrdersByMajorThenMinorThenPatch() throws {
        func ver(_ s: String) throws -> SemVer { try XCTUnwrap(SemVer(rawValue: s)) }
        XCTAssertTrue(try ver("1.0.0") < ver("2.0.0"))
        XCTAssertTrue(try ver("1.1.0") < ver("1.2.0"))
        XCTAssertTrue(try ver("1.1.1") < ver("1.1.2"))
        XCTAssertFalse(try ver("1.1.2") < ver("1.1.1"))
    }

    func testSemVerRejectsInvalidValues() {
        XCTAssertNil(SemVer(rawValue: ""))
        XCTAssertNil(SemVer(rawValue: "1.2.3.4"))
        XCTAssertNil(SemVer(rawValue: "1.a.0"))
        XCTAssertNil(SemVer(rawValue: "abc"))
        XCTAssertNil(SemVer(rawValue: "-1.2.3"))
    }

    func testDisplayStringShowsBuildAndTipChannel() throws {
        let marketing = try XCTUnwrap(SemVer(rawValue: "1.2.3"))

        XCTAssertEqual(AppVersion(marketing: marketing, build: 42, channel: .stable).displayString, "v1.2.3 (42)")
        XCTAssertEqual(AppVersion(marketing: marketing, build: nil, channel: .stable).displayString, "v1.2.3")
        XCTAssertEqual(AppVersion(marketing: marketing, build: 456, channel: .tip).displayString, "v1.2.3 (456) Tip")
        XCTAssertEqual(AppVersion(marketing: marketing, build: nil, channel: .tip).displayString, "v1.2.3 Tip")
    }

    func testBundleMetadataLoadsTipChannel() throws {
        let bundle = try makeBundle(info: [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
            "SuniyeBuildChannel": "tip"
        ])

        let version = try XCTUnwrap(AppVersion.fromBundle(bundle))

        XCTAssertEqual(version.displayString, "v1.2.3 (456) Tip")
    }

    func testFromBundleReturnsNilWithoutMarketingVersion() throws {
        let bundle = try makeBundle(info: ["CFBundleVersion": "456"])

        XCTAssertNil(AppVersion.fromBundle(bundle))
    }

    func testFromBundleReturnsNilForUnparseableMarketingVersion() throws {
        let bundle = try makeBundle(info: ["CFBundleShortVersionString": "not-a-version"])

        XCTAssertNil(AppVersion.fromBundle(bundle))
    }

    func testAppIdentityLoadsPreviewDisplayNameFromBundle() throws {
        let bundle = try makeBundle(info: [
            "CFBundleIdentifier": "dev.suniye.app.preview",
            "CFBundleDisplayName": "Suniye Preview"
        ])

        let identity = AppIdentity.fromBundle(bundle)

        XCTAssertEqual(identity.displayName, "Suniye Preview")
        XCTAssertTrue(identity.isPreview)
    }

    func testAppIdentityFallsBackToBundleNameThenDefault() throws {
        let named = AppIdentity.fromBundle(try makeBundle(info: ["CFBundleName": "Named App"]))
        XCTAssertEqual(named.displayName, "Named App")
        XCTAssertFalse(named.isPreview)

        let unnamed = AppIdentity.fromBundle(try makeBundle(info: [:]))
        XCTAssertEqual(unnamed.displayName, AppIdentity.fallbackDisplayName)

        let blank = AppIdentity.fromBundle(try makeBundle(info: ["CFBundleDisplayName": "   "]))
        XCTAssertEqual(blank.displayName, AppIdentity.fallbackDisplayName)
    }

    func testAppIdentityDetectsPreviewBySuffix() throws {
        let suffixed = AppIdentity.fromBundle(
            try makeBundle(info: ["CFBundleIdentifier": "dev.example.other.preview"])
        )
        XCTAssertTrue(suffixed.isPreview)

        let stable = AppIdentity.fromBundle(
            try makeBundle(info: ["CFBundleIdentifier": "dev.suniye.app"])
        )
        XCTAssertFalse(stable.isPreview)
    }

    private func makeBundle(info: [String: Any]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuniyeAppVersionTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }

        var fullInfo = info
        if fullInfo["CFBundleIdentifier"] == nil {
            fullInfo["CFBundleIdentifier"] = "dev.suniye.tests.bundle.\(UUID().uuidString)"
        }
        fullInfo["CFBundlePackageType"] = "BNDL"
        let data = try PropertyListSerialization.data(fromPropertyList: fullInfo, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}
