import CryptoKit
import Foundation
import XCTest
@testable import Suniye

final class UpdateServiceTests: XCTestCase {
    override func tearDown() {
        MockUpdateURLProtocol.handler = nil
        super.tearDown()
    }

    func testCheckForUpdateReturnsAvailableRelease() async throws {
        let service = makeService()
        MockUpdateURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/example-owner/example-repo/releases/latest")

            let payload: [String: Any] = [
                "tag_name": "v0.0.2",
                "body": "Release notes",
                "html_url": "https://github.com/example-owner/example-repo/releases/tag/v0.0.2",
                "published_at": "2026-02-22T00:00:00Z",
                "prerelease": false,
                "draft": false,
                "assets": [
                    [
                        "name": "Suniye.dmg",
                        "browser_download_url": "https://example.test/Suniye.dmg",
                        "size": 123,
                    ],
                    [
                        "name": "SHA256SUMS.txt",
                        "browser_download_url": "https://example.test/SHA256SUMS.txt",
                        "size": 64,
                    ],
                ],
            ]

            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let current = AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1)
        let result = try await service.checkForUpdate(currentVersion: current)

        guard case let .updateAvailable(release) = result else {
            return XCTFail("Expected updateAvailable result")
        }
        XCTAssertEqual(release.versionTag, "v0.0.2")
        XCTAssertEqual(release.assets.count, 2)
    }

    func testCheckForUpdateReturnsUpToDateWhenPrerelease() async throws {
        let service = makeService()
        MockUpdateURLProtocol.handler = { request in
            let payload: [String: Any] = [
                "tag_name": "v99.0.0",
                "body": "",
                "html_url": "https://github.com/example-owner/example-repo/releases/tag/v99.0.0",
                "published_at": "2026-02-22T00:00:00Z",
                "prerelease": true,
                "draft": false,
                "assets": [],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let current = AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1)
        let result = try await service.checkForUpdate(currentVersion: current)
        XCTAssertEqual(result, .upToDate)
    }

    func testCheckForUpdateThrowsForInvalidTag() async {
        let service = makeService()
        MockUpdateURLProtocol.handler = { request in
            let payload: [String: Any] = [
                "tag_name": "release-candidate",
                "body": "",
                "html_url": "https://github.com/example-owner/example-repo/releases/tag/release-candidate",
                "published_at": "2026-02-22T00:00:00Z",
                "prerelease": false,
                "draft": false,
                "assets": [],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let current = AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1)
        do {
            _ = try await service.checkForUpdate(currentVersion: current)
            XCTFail("Expected invalidVersionTag error")
        } catch let error as UpdateError {
            guard case .invalidVersionTag = error else {
                return XCTFail("Unexpected UpdateError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDownloadAndVerifySavesArchiveWhenChecksumMatches() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = makeService(updatesDirectory: tempDirectory)

        let archiveData = Data("archive-data".utf8)
        let checksum = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        let checksumFile = "\(checksum)  Suniye.dmg\n"

        MockUpdateURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "Suniye.dmg" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, archiveData)
            }
            if request.url?.lastPathComponent == "SHA256SUMS.txt" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(checksumFile.utf8))
            }
            throw URLError(.badURL)
        }

        let release = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: [
                UpdateAsset(name: "Suniye.dmg", downloadURL: URL(string: "https://example.test/Suniye.dmg")!, size: archiveData.count),
                UpdateAsset(name: "SHA256SUMS.txt", downloadURL: URL(string: "https://example.test/SHA256SUMS.txt")!, size: checksumFile.count),
            ]
        )

        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let savedURL = try await service.downloadAndVerify(release: release)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        let savedData = try Data(contentsOf: savedURL)
        XCTAssertEqual(savedData, archiveData)
    }

    func testDownloadAndVerifyThrowsOnChecksumMismatch() async {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = makeService(updatesDirectory: tempDirectory)

        MockUpdateURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "Suniye.dmg" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("archive-data".utf8))
            }
            if request.url?.lastPathComponent == "SHA256SUMS.txt" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("0000000000000000000000000000000000000000000000000000000000000000  Suniye.dmg\n".utf8))
            }
            throw URLError(.badURL)
        }

        let release = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: [
                UpdateAsset(name: "Suniye.dmg", downloadURL: URL(string: "https://example.test/Suniye.dmg")!, size: 12),
                UpdateAsset(name: "SHA256SUMS.txt", downloadURL: URL(string: "https://example.test/SHA256SUMS.txt")!, size: 70),
            ]
        )

        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        do {
            _ = try await service.downloadAndVerify(release: release)
            XCTFail("Expected checksum mismatch")
        } catch let error as UpdateError {
            guard case .checksumMismatch = error else {
                return XCTFail("Unexpected UpdateError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeService(updatesDirectory: URL? = nil) -> GitHubUpdateService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockUpdateURLProtocol.self]
        let session = URLSession(configuration: config)
        return GitHubUpdateService(
            session: session,
            bundle: makeBundle(),
            updatesDirectoryOverride: updatesDirectory
        )
    }

    private func makeBundle() -> Bundle {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = tempRoot.appendingPathComponent("UpdateConfig.bundle", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "dev.suniye.tests",
            "VSUpdateRepoOwner": "example-owner",
            "VSUpdateRepoName": "example-repo",
            "VSUpdatePreferredAssetName": "Suniye.dmg",
        ]
        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        NSDictionary(dictionary: info).write(to: plistURL, atomically: true)

        guard let bundle = Bundle(url: bundleURL) else {
            fatalError("Unable to create test bundle")
        }
        return bundle
    }
}

private final class MockUpdateURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
