import XCTest
@testable import Tunerfenster

private func fixtureRelease(_ tag: String = "v1.8.0", assets: [GitHubRelease.Asset]? = nil,
                     draft: Bool = false, prerelease: Bool = false) -> GitHubRelease {
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    return GitHubRelease(tagName: tag, draft: draft, prerelease: prerelease, assets: assets ?? UpdateArchitecture.all.map {
        let name = "Tunerfenster-\(version)-\($0.rawValue).dmg"
        return GitHubRelease.Asset(name: name, browserDownloadURL: "https://github.com/NemoN/Tunerfenster/releases/download/\(tag)/\(name)", state: "uploaded", size: 1000)
    })
}

private extension UpdateArchitecture {
    static let all: [Self] = [.appleSilicon, .intel]
}

final class UpdateSelectionTests: XCTestCase {
    func testVersionsAreComparedNumericallyAndNeverOfferADowngrade() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.9")), try XCTUnwrap(AppVersion("v1.10.0")))
        XCTAssertEqual(AppVersion("1.8"), AppVersion("1.8.0.0"))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.8.0")), try XCTUnwrap(AppVersion("1.8.0.1")))
        for invalid in ["", "v", "1..8", "1.8-beta", "1.8.0+build", "-1.8", "1.8/other", "１.８", "1.2.3.4.5", "99999999999999999999999999"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
        for current in ["1.8", "1.8.0", "2.0.0"] {
            guard case .upToDate = try fixtureRelease().evaluate(currentVersion: XCTUnwrap(AppVersion(current)), architecture: .intel) else {
                return XCTFail("Must not offer a downgrade or the installed release")
            }
        }
    }

    func testCorrectInstallerIsSelectedForBothCPUsAndRosetta() throws {
        if let expected = ProcessInfo.processInfo.environment["TUNERFENSTER_EXPECT_UPDATE_ARCH"] {
            XCTAssertEqual(UpdateArchitecture.current.rawValue, expected, "Check the actual compiled process, including Rosetta")
        }
        XCTAssertEqual(UpdateArchitecture.resolve(nativeARM: true, translated: false), .appleSilicon)
        XCTAssertEqual(UpdateArchitecture.resolve(nativeARM: false, translated: true), .appleSilicon)
        XCTAssertEqual(UpdateArchitecture.resolve(nativeARM: false, translated: false), .intel)
        for architecture in UpdateArchitecture.all {
            guard case .available(let update) = try fixtureRelease().evaluate(currentVersion: XCTUnwrap(AppVersion("1.7.1")), architecture: architecture) else {
                return XCTFail("Expected update")
            }
            XCTAssertEqual(update.architecture, architecture)
            XCTAssertEqual(update.downloadURL?.lastPathComponent, "Tunerfenster-1.8.0-\(architecture.rawValue).dmg")
        }
    }

    func testTwoComponentMajorReleaseOffersCorrectInstallerAndIsNotOfferedAgain() throws {
        let release = fixtureRelease("v2.0")
        for architecture in UpdateArchitecture.all {
            guard case .available(let update) = try release.evaluate(currentVersion: XCTUnwrap(AppVersion("1.9.0")), architecture: architecture) else {
                return XCTFail("Expected major version update")
            }
            XCTAssertEqual(update.version.description, "2.0")
            XCTAssertEqual(update.downloadURL?.lastPathComponent, "Tunerfenster-2.0-\(architecture.rawValue).dmg")
            for installed in ["2.0", "2.0.0"] {
                guard case .upToDate = try release.evaluate(currentVersion: XCTUnwrap(AppVersion(installed)), architecture: architecture) else {
                    return XCTFail("Installed major release must not be offered again")
                }
            }
        }
    }

    func testWrongCPUForeignURLsAndIncompleteUploadsNeverBecomeDownloads() throws {
        let name = "Tunerfenster-1.8.0-arm64.dmg"
        let valid = "https://github.com/NemoN/Tunerfenster/releases/download/v1.8.0/\(name)"
        let foreignURLs = [valid.replacingOccurrences(of: "https:", with: "http:"),
                           valid.replacingOccurrences(of: "github.com/", with: "github.com.evil.example/"),
                           valid.replacingOccurrences(of: "NemoN/", with: "someone/"),
                           valid.replacingOccurrences(of: "v1.8.0/", with: "v1.7.0/"), valid + "?redirect=elsewhere"]
        var cases = foreignURLs.map { [GitHubRelease.Asset(name: name, browserDownloadURL: $0, state: "uploaded", size: 100)] }
        cases.append([GitHubRelease.Asset(name: name, browserDownloadURL: valid, state: "new", size: 100)])
        cases.append([GitHubRelease.Asset(name: name, browserDownloadURL: valid, state: "uploaded", size: 0)])
        cases.append([fixtureRelease().assets[1]]) // Intel is not a fallback for ARM.
        cases.append([fixtureRelease().assets[0], fixtureRelease().assets[0]]) // Ambiguous duplicates.
        cases.append([])
        for assets in cases {
            guard case .available(let update) = try fixtureRelease(assets: assets).evaluate(currentVersion: XCTUnwrap(AppVersion("1.7.1")), architecture: .appleSilicon) else {
                return XCTFail("Release should still be visible")
            }
            XCTAssertNil(update.downloadURL)
            XCTAssertEqual(update.releaseURL.absoluteString, "https://github.com/NemoN/Tunerfenster/releases/tag/v1.8.0")
        }
    }

    func testDraftPrereleaseAndInvalidTagsAreRejected() throws {
        for candidate in [fixtureRelease(draft: true), fixtureRelease(prerelease: true), fixtureRelease("v1.9.0-beta"), fixtureRelease("v1.9.0/../../elsewhere")] {
            XCTAssertThrowsError(try candidate.evaluate(currentVersion: XCTUnwrap(AppVersion("1.7.1")), architecture: .intel)) {
                XCTAssertEqual($0 as? UpdateFailure, .invalidRelease)
            }
        }
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "UpdateTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testDailyChecksPersistAcrossLaunchesAndManualCheckOverridesPreference() async throws {
        let store = try defaults()
        let now = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        let updater = UpdateChecker(defaults: store, currentVersion: "1.7.1", fetchLatest: { calls += 1; return fixtureRelease() })
        XCTAssertTrue(updater.automaticChecks)
        await updater.check(automatically: true, now: now)
        await updater.check(automatically: true, now: now.addingTimeInterval(60))
        XCTAssertEqual(calls, 1)
        let reopened = UpdateChecker(defaults: store, currentVersion: "1.7.1", fetchLatest: { calls += 1; return fixtureRelease() })
        XCTAssertFalse(reopened.automaticCheckIsDue(at: now.addingTimeInterval(60)))
        XCTAssertTrue(reopened.automaticCheckIsDue(at: now.addingTimeInterval(UpdateChecker.interval)))
        XCTAssertTrue(reopened.automaticCheckIsDue(at: now.addingTimeInterval(-60)), "Clock changes must not suppress checks indefinitely")
        reopened.automaticChecks = false
        await reopened.check(automatically: true, now: now.addingTimeInterval(UpdateChecker.interval))
        XCTAssertEqual(calls, 1)
        await reopened.check(now: now.addingTimeInterval(120))
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(UpdateChecker(defaults: store, currentVersion: "1.7.1").automaticChecks)
    }

    func testKnownUpdateSurvivesRestartAndNetworkFailureButNotInstallingIt() async throws {
        let store = try defaults()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let updater = UpdateChecker(defaults: store, currentVersion: "1.7.1", architecture: .intel, fetchLatest: { fixtureRelease() })
        await updater.check(now: now)
        XCTAssertTrue(updater.showBanner)
        updater.dismissBanner()
        XCTAssertFalse(updater.showBanner)
        let reopened = UpdateChecker(defaults: store, currentVersion: "1.7.1", architecture: .appleSilicon, fetchLatest: { throw UpdateFailure.offline })
        XCTAssertTrue(reopened.showBanner)
        XCTAssertTrue(try XCTUnwrap(reopened.available?.downloadURL).lastPathComponent.contains("arm64"))
        await reopened.check(now: now.addingTimeInterval(5))
        XCTAssertEqual(reopened.failure, .offline)
        XCTAssertNotNil(reopened.available)
        XCTAssertEqual(reopened.lastChecked, now, "A failed attempt is not a successful check")
        let installed = UpdateChecker(defaults: store, currentVersion: "1.8.0")
        XCTAssertNil(installed.available)
        XCTAssertFalse(installed.showBanner)
        guard case .upToDate = installed.result else { return XCTFail("Installed update must not be offered again") }
    }

    func testAutomaticFailuresAreThrottledAndCancelledRequestsCanRetry() async throws {
        let store = try defaults()
        let now = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        let updater = UpdateChecker(defaults: store, currentVersion: "1.7.1", fetchLatest: { calls += 1; throw UpdateFailure.rateLimited })
        await updater.check(automatically: true, now: now)
        await updater.check(automatically: true, now: now.addingTimeInterval(60))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(updater.failure, .rateLimited)
        XCTAssertNil(updater.lastChecked)
        let cancelled = UpdateChecker(defaults: try defaults(), currentVersion: "1.7.1", fetchLatest: { throw CancellationError() })
        await cancelled.check(automatically: true, now: now)
        XCTAssertTrue(cancelled.automaticCheckIsDue(at: now))
        XCTAssertFalse(cancelled.isChecking)
        XCTAssertNil(cancelled.failure)
    }

    func testConcurrentChecksShareOneRequest() async throws {
        let entered = expectation(description: "Request started")
        var continuation: CheckedContinuation<GitHubRelease?, Error>?
        var calls = 0
        let updater = UpdateChecker(defaults: try defaults(), currentVersion: "1.7.1", fetchLatest: {
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() }
        })
        let request = Task { await updater.check() }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertTrue(updater.isChecking)
        await updater.check()
        XCTAssertEqual(calls, 1)
        continuation?.resume(returning: fixtureRelease())
        await request.value
        XCTAssertFalse(updater.isChecking)
        XCTAssertNotNil(updater.available)
    }

    func testNoReleasesAndCorruptCacheDoNotInventAnUpdate() async throws {
        let store = try defaults()
        store.set(Data("broken".utf8), forKey: "updateCachedReleaseV1")
        let updater = UpdateChecker(defaults: store, currentVersion: "1.7.1", fetchLatest: { nil })
        XCTAssertNil(updater.result)
        await updater.check()
        guard case .noReleases = updater.result else { return XCTFail("Expected no releases") }
        XCTAssertNil(store.data(forKey: "updateCachedReleaseV1"))
        let invalid = UpdateChecker(defaults: store, currentVersion: "invalid", fetchLatest: { XCTFail("Must not request with invalid installed version"); return nil })
        await invalid.check()
        XCTAssertEqual(invalid.failure, .invalidCurrentVersion)
    }
}

private final class UpdateURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class UpdateNetworkTests: XCTestCase {
    func testPublicRequestAndHTTPFailures() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); UpdateURLProtocol.respond = nil }
        let client = GitHubUpdateClient(session: session)
        let valid = try JSONEncoder().encode(fixtureRelease())
        for (status, data, failure) in [(200, valid, nil), (404, Data(), nil), (403, Data(), UpdateFailure.rateLimited),
                                      (429, Data(), .rateLimited), (503, Data(), .server), (200, Data("not JSON".utf8), .invalidRelease)] {
            UpdateURLProtocol.respond = { request in
                XCTAssertEqual(request.url, GitHubUpdateClient.endpoint)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                return (status, data)
            }
            do {
                let result = try await client.latestRelease()
                XCTAssertNil(failure)
                XCTAssertEqual(result?.tagName, status == 404 ? nil : "v1.8.0")
            } catch { XCTAssertEqual(error as? UpdateFailure, failure) }
        }
        UpdateURLProtocol.respond = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client.latestRelease(); XCTFail("Expected network failure") }
        catch { XCTAssertEqual(error as? UpdateFailure, .offline) }
        let production = GitHubUpdateClient().session.configuration
        XCTAssertNil(production.httpCookieStorage)
        XCTAssertNil(production.urlCredentialStorage)
        XCTAssertFalse(production.httpShouldSetCookies)
    }

    func testLivePublicReleaseWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["TUNERFENSTER_LIVE_UPDATES"] == "1" else { throw XCTSkip("Set TUNERFENSTER_LIVE_UPDATES=1 for the public GitHub check") }
        let fetched = try await GitHubUpdateClient().latestRelease()
        let latest = try XCTUnwrap(fetched)
        for architecture in UpdateArchitecture.all {
            guard case .available(let update) = try latest.evaluate(currentVersion: XCTUnwrap(AppVersion("0.0.0")), architecture: architecture) else {
                return XCTFail("Expected published release")
            }
            XCTAssertNotNil(update.downloadURL, "Live release must offer the correct CPU installer")
        }
    }
}
