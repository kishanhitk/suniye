import CryptoKit
import Foundation

struct UpdateAsset: Equatable {
    let name: String
    let downloadURL: URL
    let size: Int
}

struct UpdateRelease: Equatable {
    let versionTag: String
    let publishedAt: Date?
    let notes: String
    let htmlURL: URL
    let assets: [UpdateAsset]
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(UpdateRelease)
}

enum UpdateError: LocalizedError {
    case network(String)
    case invalidResponse
    case invalidVersionTag(String)
    case missingAsset(String)
    case checksumMissing(String)
    case checksumMismatch(expected: String, actual: String)
    case fileIO(String)

    var errorDescription: String? {
        switch self {
        case let .network(message):
            return message
        case .invalidResponse:
            return "Update server returned an invalid response."
        case let .invalidVersionTag(tag):
            return "Release version tag is invalid: \(tag)"
        case let .missingAsset(name):
            return "Required release asset is missing: \(name)"
        case let .checksumMissing(name):
            return "Checksum entry missing for: \(name)"
        case let .checksumMismatch(expected, actual):
            return "Checksum mismatch. Expected \(expected), got \(actual)."
        case let .fileIO(message):
            return message
        }
    }
}

protocol UpdateServiceProtocol {
    func checkForUpdate(currentVersion: AppVersion) async throws -> UpdateCheckResult
    func downloadAndVerify(release: UpdateRelease) async throws -> URL
}

final class GitHubUpdateService: UpdateServiceProtocol {
    private static let checksumFileName = "SHA256SUMS.txt"
    private static let fallbackAssetName = "Suniye.app.zip"

    private let session: URLSession
    private let fileManager: FileManager
    private let updatesDirectoryOverride: URL?
    private let configuration: UpdateServiceConfiguration?

    init(
        session: URLSession = .shared,
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        updatesDirectoryOverride: URL? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.updatesDirectoryOverride = updatesDirectoryOverride
        self.configuration = UpdateServiceConfiguration(bundle: bundle)
    }

    func checkForUpdate(currentVersion: AppVersion) async throws -> UpdateCheckResult {
        let config = try requireConfiguration()
        let endpoint = try latestReleaseURL(owner: config.repoOwner, repoName: config.repoName)
        let data = try await requestData(
            url: endpoint,
            useGitHubHeaders: true,
            statusMapper: mapGitHubAPIStatus,
            actionLabel: "Update check"
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload: GitHubReleasePayload
        do {
            payload = try decoder.decode(GitHubReleasePayload.self, from: data)
        } catch {
            throw UpdateError.invalidResponse
        }

        if payload.draft || payload.prerelease {
            return .upToDate
        }

        guard let remoteVersion = SemVer(rawValue: payload.tagName) else {
            throw UpdateError.invalidVersionTag(payload.tagName)
        }
        guard remoteVersion > currentVersion.marketing else {
            return .upToDate
        }

        let release = UpdateRelease(
            versionTag: payload.tagName,
            publishedAt: payload.publishedAt,
            notes: payload.body ?? "",
            htmlURL: payload.htmlURL,
            assets: payload.assets.map { asset in
                UpdateAsset(name: asset.name, downloadURL: asset.browserDownloadURL, size: asset.size)
            }
        )

        _ = try selectDownloadAsset(for: release, preferredName: config.preferredAssetName)
        _ = try checksumAsset(from: release.assets)

        return .updateAvailable(release)
    }

    func downloadAndVerify(release: UpdateRelease) async throws -> URL {
        let config = try requireConfiguration()
        let downloadAsset = try selectDownloadAsset(for: release, preferredName: config.preferredAssetName)
        let checksumAsset = try checksumAsset(from: release.assets)

        let archiveData = try await requestData(
            url: downloadAsset.downloadURL,
            useGitHubHeaders: false,
            statusMapper: mapGenericStatus,
            actionLabel: "Update download"
        )
        let checksumData = try await requestData(
            url: checksumAsset.downloadURL,
            useGitHubHeaders: false,
            statusMapper: mapGenericStatus,
            actionLabel: "Checksum download"
        )

        guard let checksumText = String(data: checksumData, encoding: .utf8) else {
            throw UpdateError.invalidResponse
        }

        let expectedChecksum = try checksumValue(forFileNamed: downloadAsset.name, from: checksumText)
        let actualChecksum = sha256Hex(for: archiveData)
        guard expectedChecksum.caseInsensitiveCompare(actualChecksum) == .orderedSame else {
            throw UpdateError.checksumMismatch(expected: expectedChecksum.lowercased(), actual: actualChecksum.lowercased())
        }

        let updatesDirectory = try resolveUpdatesDirectory()
        let destination = updatesDirectory.appendingPathComponent(downloadAsset.name, isDirectory: false)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try archiveData.write(to: destination, options: .atomic)
            return destination
        } catch {
            throw UpdateError.fileIO("Failed to save update archive.")
        }
    }

    private func requireConfiguration() throws -> UpdateServiceConfiguration {
        guard let configuration else {
            throw UpdateError.invalidResponse
        }
        return configuration
    }

    private func latestReleaseURL(owner: String, repoName: String) throws -> URL {
        guard
            let ownerEncoded = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let repoEncoded = repoName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://api.github.com/repos/\(ownerEncoded)/\(repoEncoded)/releases/latest")
        else {
            throw UpdateError.invalidResponse
        }
        return url
    }

    private func selectDownloadAsset(for release: UpdateRelease, preferredName: String) throws -> UpdateAsset {
        if let preferred = release.assets.first(where: { $0.name == preferredName }) {
            return preferred
        }
        if preferredName != Self.fallbackAssetName,
           let fallback = release.assets.first(where: { $0.name == Self.fallbackAssetName }) {
            return fallback
        }
        throw UpdateError.missingAsset(preferredName)
    }

    private func checksumAsset(from assets: [UpdateAsset]) throws -> UpdateAsset {
        guard let checksumAsset = assets.first(where: { $0.name == Self.checksumFileName }) else {
            throw UpdateError.missingAsset(Self.checksumFileName)
        }
        return checksumAsset
    }

    private func checksumValue(forFileNamed name: String, from checksumText: String) throws -> String {
        let lines = checksumText.split(whereSeparator: \.isNewline)
        for line in lines {
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else {
                continue
            }

            let hashValue = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard hashValue.count == 64 else {
                continue
            }

            var fileToken = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if fileToken.hasPrefix("*") {
                fileToken.removeFirst()
            }
            fileToken = URL(fileURLWithPath: fileToken).lastPathComponent

            if fileToken == name {
                return hashValue.lowercased()
            }
        }

        throw UpdateError.checksumMissing(name)
    }

    private func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func resolveUpdatesDirectory() throws -> URL {
        if let updatesDirectoryOverride {
            do {
                try fileManager.createDirectory(at: updatesDirectoryOverride, withIntermediateDirectories: true)
                return updatesDirectoryOverride
            } catch {
                throw UpdateError.fileIO("Unable to create updates directory.")
            }
        }

        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw UpdateError.fileIO("Unable to resolve Application Support directory.")
        }

        let directory = appSupport
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("updates", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw UpdateError.fileIO("Unable to create updates directory.")
        }
    }

    private func requestData(
        url: URL,
        useGitHubHeaders: Bool,
        statusMapper: (Int) -> UpdateError,
        actionLabel: String
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Suniye/ManualUpdater", forHTTPHeaderField: "User-Agent")
        if useGitHubHeaders {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw statusMapper(http.statusCode)
            }
            return data
        } catch let error as UpdateError {
            throw error
        } catch let error as URLError {
            throw UpdateError.network("\(actionLabel) failed: \(error.localizedDescription)")
        } catch {
            throw UpdateError.network("\(actionLabel) failed.")
        }
    }

    private func mapGitHubAPIStatus(_ statusCode: Int) -> UpdateError {
        switch statusCode {
        case 403:
            return .network("GitHub API rate limited. Try again later.")
        case 404:
            return .network("Update metadata not found.")
        default:
            return .invalidResponse
        }
    }

    private func mapGenericStatus(_ statusCode: Int) -> UpdateError {
        switch statusCode {
        case 403:
            return .network("Download denied by server.")
        case 404:
            return .network("Requested update file was not found.")
        default:
            return .invalidResponse
        }
    }
}

private struct UpdateServiceConfiguration {
    let repoOwner: String
    let repoName: String
    let preferredAssetName: String

    init?(bundle: Bundle) {
        guard
            let owner = bundle.object(forInfoDictionaryKey: "VSUpdateRepoOwner") as? String,
            let repoName = bundle.object(forInfoDictionaryKey: "VSUpdateRepoName") as? String,
            let preferredAssetName = bundle.object(forInfoDictionaryKey: "VSUpdatePreferredAssetName") as? String
        else {
            return nil
        }

        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRepoName = repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPreferred = preferredAssetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwner.isEmpty, !trimmedRepoName.isEmpty, !trimmedPreferred.isEmpty else {
            return nil
        }

        self.repoOwner = trimmedOwner
        self.repoName = trimmedRepoName
        self.preferredAssetName = trimmedPreferred
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let prerelease: Bool
    let draft: Bool
    let assets: [GitHubReleaseAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case assets
    }
}

private struct GitHubReleaseAssetPayload: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}
