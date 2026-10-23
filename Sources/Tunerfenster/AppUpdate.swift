import Combine
import Darwin
import Foundation

struct AppVersion: Comparable, CustomStringConvertible {
    let description: String
    private let numbers: [Int]

    init?(_ value: String) {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count), parts.allSatisfy({
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && Int($0) != nil
        }) else { return nil }
        description = version
        var numbers = parts.map { Int($0)! }
        while numbers.count > 1 && numbers.last == 0 { numbers.removeLast() }
        self.numbers = numbers
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.numbers == rhs.numbers }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum UpdateArchitecture: String {
    case appleSilicon = "arm64"
    case intel = "x86_64"

    var title: String { self == .appleSilicon ? "Apple Silicon (arm64)" : "Intel (x86_64)" }

    static func resolve(nativeARM: Bool, translated: Bool) -> Self {
        nativeARM || translated ? .appleSilicon : .intel
    }

    static var current: Self {
        #if arch(arm64)
        return .appleSilicon
        #else
        // Apple's Rosetta flag describes the hardware even in an Intel process.
        var translated: Int32 = 0
        var size = MemoryLayout.size(ofValue: translated)
        let success = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0
        return resolve(nativeARM: false, translated: success && translated == 1)
        #endif
    }
}

struct GitHubRelease: Codable {
    struct Asset: Codable {
        let name: String
        let browserDownloadURL: String
        let state: String
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name, state, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name"
    }

    func evaluate(currentVersion: AppVersion, architecture: UpdateArchitecture) throws -> UpdateResult {
        guard !draft, !prerelease, let version = AppVersion(tagName) else { throw UpdateFailure.invalidRelease }
        guard currentVersion < version else { return .upToDate }
        let releaseURL = URL(string: "https://github.com/NemoN/Tunerfenster/releases/tag/\(tagName)")!
        let filename = "Tunerfenster-\(version)-\(architecture.rawValue).dmg"
        let expected = "https://github.com/NemoN/Tunerfenster/releases/download/\(tagName)/\(filename)"
        // Exact repository, tag, CPU and filename matching prevents a foreign URL
        // or another architecture's installer from becoming the download action.
        let matches = assets.filter { $0.name == filename && $0.state == "uploaded" && $0.size > 0 && $0.browserDownloadURL == expected }
        let downloadURL = matches.count == 1 ? URL(string: expected) : nil
        return .available(AppUpdate(version: version, architecture: architecture, releaseURL: releaseURL, downloadURL: downloadURL))
    }
}

struct AppUpdate {
    let version: AppVersion
    let architecture: UpdateArchitecture
    let releaseURL: URL
    let downloadURL: URL?
}

enum UpdateResult {
    case upToDate
    case noReleases
    case available(AppUpdate)
}

enum UpdateFailure: Error, Equatable {
    case offline, rateLimited, server, invalidRelease, invalidCurrentVersion

    var message: String {
        let key = switch self {
        case .offline: "updateOffline"
        case .rateLimited: "updateRateLimited"
        case .server: "updateServerError"
        case .invalidRelease: "updateInvalidRelease"
        case .invalidCurrentVersion: "updateInvalidCurrentVersion"
        }
        return L10n.text(key)
    }
}

struct GitHubUpdateClient {
    static let endpoint = URL(string: "https://api.github.com/repos/NemoN/Tunerfenster/releases/latest")!
    let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration)
    }

    func latestRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Tunerfenster-UpdateCheck", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw UpdateFailure.offline
        }
        guard let http = response as? HTTPURLResponse, http.url == Self.endpoint else { throw UpdateFailure.server }
        switch http.statusCode {
        case 404: return nil
        case 403, 429: throw UpdateFailure.rateLimited
        case 200: break
        default: throw UpdateFailure.server
        }
        guard data.count <= 2_000_000, let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw UpdateFailure.invalidRelease
        }
        return release
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let interval: TimeInterval = 24 * 60 * 60
    private static let automaticKey = "automaticUpdateChecks"
    private static let attemptKey = "updateLastAttempt"
    private static let successKey = "updateLastSuccess"
    private static let cacheKey = "updateCachedReleaseV1"

    @Published var automaticChecks: Bool { didSet { defaults.set(automaticChecks, forKey: Self.automaticKey) } }
    @Published private(set) var isChecking = false
    @Published private(set) var result: UpdateResult?
    @Published private(set) var failure: UpdateFailure?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var dismissedVersion: AppVersion?
    let currentVersion: String
    let architecture: UpdateArchitecture
    private let defaults: UserDefaults
    private let fetchLatest: () async throws -> GitHubRelease?

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         architecture: UpdateArchitecture = .current,
         fetchLatest: (() async throws -> GitHubRelease?)? = nil) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.architecture = architecture
        let client = GitHubUpdateClient()
        self.fetchLatest = fetchLatest ?? { try await client.latestRelease() }
        automaticChecks = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        lastChecked = defaults.object(forKey: Self.successKey) as? Date
        if let data = defaults.data(forKey: Self.cacheKey),
           let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
           let current = AppVersion(currentVersion) {
            result = try? release.evaluate(currentVersion: current, architecture: architecture)
        }
    }

    var available: AppUpdate? { if case .available(let update) = result { return update }; return nil }
    var showBanner: Bool { available.map { $0.version != dismissedVersion } ?? false }
    func dismissBanner() { dismissedVersion = available?.version }

    func automaticCheckIsDue(at now: Date) -> Bool {
        guard automaticChecks else { return false }
        guard let previous = defaults.object(forKey: Self.attemptKey) as? Date else { return true }
        return previous > now || now.timeIntervalSince(previous) >= Self.interval
    }

    func check(automatically: Bool = false, now: Date = Date()) async {
        guard !isChecking, !automatically || automaticCheckIsDue(at: now) else { return }
        guard let current = AppVersion(currentVersion) else { failure = .invalidCurrentVersion; return }
        isChecking = true
        failure = nil
        defer { isChecking = false }
        do {
            let release = try await fetchLatest()
            try Task.checkCancellation()
            let next = try release?.evaluate(currentVersion: current, architecture: architecture) ?? .noReleases
            result = next
            lastChecked = now
            defaults.set(now, forKey: Self.successKey)
            defaults.set(now, forKey: Self.attemptKey)
            if let release, let data = try? JSONEncoder().encode(release) { defaults.set(data, forKey: Self.cacheKey) }
            else { defaults.removeObject(forKey: Self.cacheKey) }
        } catch is CancellationError {
            // Quitting during a request must not suppress the next launch's check.
        } catch {
            failure = error as? UpdateFailure ?? .offline
            defaults.set(now, forKey: Self.attemptKey)
        }
    }

    func runAutomaticChecks() async {
        while !Task.isCancelled {
            await check(automatically: true)
            do { try await Task.sleep(for: .seconds(3600)) }
            catch { return }
        }
    }
}
