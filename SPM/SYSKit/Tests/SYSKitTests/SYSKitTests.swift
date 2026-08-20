import XCTest
@testable import SYSKit

// MARK: - Version

final class SYSVersionTests: XCTestCase {
    /// The reason this type exists: string comparison sorts "1.10.0" below
    /// "1.9.0", which behaves correctly until a minor reaches double digits.
    func testDoubleDigitMinorIsNotSortedAsText() {
        XCTAssertEqual(SYSVersion.compare("1.10.0", "1.9.0"), .orderedDescending)
        XCTAssertTrue(SYSVersion.isOlder("1.9.0", than: "1.10.0"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(SYSVersion.compare("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(SYSVersion.compare("2", "2.0.0"), .orderedSame)
    }

    func testOrdering() {
        XCTAssertEqual(SYSVersion.compare("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(SYSVersion.compare("1.0.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(SYSVersion.compare("3.4.5", "3.4.5"), .orderedSame)
    }

    func testNonNumericComponentsDoNotCrash() {
        XCTAssertEqual(SYSVersion.compare("1.x.0", "1.0.0"), .orderedSame)
    }
}

// MARK: - Config decoding

final class SYSConfigDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> SYSConfigData {
        try JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8))
    }

    /// A config that fails to decode is a config that can no longer be fixed
    /// remotely, so every field must be optional.
    func testEmptyObjectDecodes() throws {
        let config = try decode("{}")
        XCTAssertNil(config.configVersion)
        XCTAssertNil(config.flags)
    }

    func testUnknownKeysAreIgnored() throws {
        let config = try decode(#"{"configVersion":2,"somethingAddedLater":{"a":1}}"#)
        XCTAssertEqual(config.configVersion, 2)
    }

    func testLocalisedMessageResolvesByLanguage() throws {
        let config = try decode(#"{"update":{"message":{"en":"Update","hi":"अपडेट"}}}"#)
        XCTAssertEqual(config.update?.message?.resolved(for: ["hi"]), "अपडेट")
        XCTAssertEqual(config.update?.message?.resolved(for: ["en"]), "Update")
    }

    /// An unsupported language should fall back rather than show nothing.
    func testLocalisedMessageFallsBackToEnglish() throws {
        let config = try decode(#"{"update":{"message":{"en":"Update","hi":"अपडेट"}}}"#)
        XCTAssertEqual(config.update?.message?.resolved(for: ["fr"]), "Update")
    }

    /// Older configs wrote a bare string; those must keep working.
    func testBareStringMessageStillDecodes() throws {
        let config = try decode(#"{"update":{"message":"Plain text"}}"#)
        XCTAssertEqual(config.update?.message?.resolved(for: ["en"]), "Plain text")
    }

    func testAppSectionHoldsMixedTypes() throws {
        let config = try decode(#"{"app":{"endpoint":"/packs","max":12,"beta":true}}"#)
        XCTAssertEqual(config.app?["endpoint"]?.stringValue, "/packs")
        XCTAssertEqual(config.app?["max"]?.intValue, 12)
        XCTAssertEqual(config.app?["beta"]?.boolValue, true)
    }
}

// MARK: - Update gates

final class SYSUpdateTests: XCTestCase {
    private func config(_ json: String, version: String) -> SYSConfig {
        let config = SYSConfig(bundle: StubBundle(version: version))
        config.applyForTesting(try! JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8)))
        return config
    }

    func testBelowMinimumIsRequired() {
        let sut = config(#"{"update":{"minimumVersion":"2.0.0"}}"#, version: "1.9.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .required)
    }

    func testBelowRecommendedIsRecommended() {
        let sut = config(#"{"update":{"minimumVersion":"1.0.0","recommendedVersion":"2.0.0"}}"#, version: "1.5.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .recommended)
    }

    func testCurrentVersionIsFine() {
        let sut = config(#"{"update":{"minimumVersion":"1.0.0","recommendedVersion":"1.5.0"}}"#, version: "1.5.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .none)
    }

    /// Double-digit minors are exactly where a string comparison would wrongly
    /// block every user.
    func testDoubleDigitMinorIsNotWronglyBlocked() {
        let sut = config(#"{"update":{"minimumVersion":"1.9.0"}}"#, version: "1.10.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .none)
    }

    func testNoUpdateSectionMeansNoGate() {
        let sut = config("{}", version: "1.0.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .none)
    }

    func testMaintenanceOnlyWhenExplicitlyEnabled() {
        XCTAssertFalse(SYSMaintenance.isActive(config: config("{}", version: "1.0.0")))
        XCTAssertFalse(SYSMaintenance.isActive(config: config(#"{"maintenance":{"enabled":false}}"#, version: "1.0.0")))
        XCTAssertTrue(SYSMaintenance.isActive(config: config(#"{"maintenance":{"enabled":true}}"#, version: "1.0.0")))
    }
}

// MARK: - Settings

final class SYSSettingsTests: XCTestCase {
    private var settings: SYSSettings!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SYSKitTests-\(UUID().uuidString)")
        settings = SYSSettings(defaults: defaults)
    }

    func testDefaultIsUsedWhenUnset() {
        XCTAssertEqual(settings[SYSSettingsKey<Int>("missing", default: 42)], 42)
        XCTAssertFalse(settings[SYSSettingsKey<Bool>("missing", default: false)])
    }

    /// `false` must be distinguishable from "never set" — the classic
    /// UserDefaults trap.
    func testStoredFalseIsNotTreatedAsMissing() {
        let key = SYSSettingsKey<Bool>("flag", default: true)
        settings[key] = false
        XCTAssertFalse(settings[key])
    }

    func testRoundTrips() {
        let text = SYSSettingsKey<String>("name", default: "")
        settings[text] = "colorful"
        XCTAssertEqual(settings[text], "colorful")
    }

    func testRemove() {
        let key = SYSSettingsKey<Int>("count", default: 0)
        settings[key] = 5
        XCTAssertTrue(settings.contains(key))
        settings.remove(key)
        XCTAssertFalse(settings.contains(key))
        XCTAssertEqual(settings[key], 0)
    }
}

// MARK: - Network helpers

final class SYSNetworkTests: XCTestCase {
    /// Storage returns 404 for an unescaped path — slashes must be %2F.
    func testStorageURLEncodesSlashes() {
        let url = SYSNetwork.storageURL(bucket: "demo.firebasestorage.app", path: "packs/animals.zip")
        XCTAssertEqual(
            url?.absoluteString,
            "https://firebasestorage.googleapis.com/v0/b/demo.firebasestorage.app/o/packs%2Fanimals.zip?alt=media"
        )
    }

    func testBackoffGrows() {
        XCTAssertLessThan(SYSNetwork.backoff(1), SYSNetwork.backoff(2))
        XCTAssertLessThan(SYSNetwork.backoff(2), SYSNetwork.backoff(3))
    }
}

// MARK: - Helpers

/// Bundle stub so version-dependent logic is testable without a host app.
private final class StubBundle: Bundle, @unchecked Sendable {
    private let version: String
    init(version: String) {
        self.version = version
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func object(forInfoDictionaryKey key: String) -> Any? {
        key == "CFBundleShortVersionString" ? version : nil
    }
}

// MARK: - SYSHash

final class SYSHashTests: XCTestCase {
    // FIPS 180-4 vectors. The fallback is only compiled on non-Apple platforms,
    // so it is tested directly rather than through sha256Hex — otherwise CI on
    // macOS would verify CryptoKit and never touch the code that actually ships
    // to a Linux build.
    func testKnownVectors() {
        let cases: [(String, String)] = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
             "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        ]
        for (input, expected) in cases {
            let data = Data(input.utf8)
            XCTAssertEqual(SYSHash.sha256Hex(data), expected, "sha256Hex(\(input.prefix(12)))")
            XCTAssertEqual(SYSHash.fallbackSHA256Hex(data), expected, "fallback(\(input.prefix(12)))")
        }
    }

    func testFallbackMatchesPlatformImplementation() {
        // Multi-block input, to exercise the chunk loop rather than one padded block.
        let data = Data((0 ..< 5000).map { UInt8($0 % 251) })
        XCTAssertEqual(SYSHash.sha256Hex(data), SYSHash.fallbackSHA256Hex(data))
    }

    func testLengthPaddingBoundaries() {
        // 55/56/57 and 63/64/65 bytes straddle the padding block boundary, where
        // a wrong implementation still passes short inputs.
        for length in [55, 56, 57, 63, 64, 65, 119, 120] {
            let data = Data(repeating: 0x61, count: length)
            XCTAssertEqual(SYSHash.sha256Hex(data), SYSHash.fallbackSHA256Hex(data), "length \(length)")
        }
    }
}

// MARK: - SYSAssets

final class SYSAssetsTests: XCTestCase {
    private func manifest(required: [String] = []) -> SYSAssetManifest {
        SYSAssetManifest(manifestVersion: 1, generatedAt: nil, items: [
            SYSAssetPack(id: "a", title: "A", bundle: "/packs/a-1111.json", bytes: 10, sha256: nil,
                         required: required.contains("a")),
            SYSAssetPack(id: "b", title: "B", bundle: "/packs/b-2222.json", bytes: 20, sha256: nil,
                         required: required.contains("b")),
        ])
    }

    func testManifestRoundTrips() throws {
        let original = manifest(required: ["a"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SYSAssetManifest.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testManifestDecodesWithoutOptionalFields() throws {
        // The server may omit title/bytes/sha256/required entirely; a decode
        // failure here would strand the app with no content and no explanation.
        let json = #"{"manifestVersion":1,"items":[{"id":"a","bundle":"/packs/a.json"}]}"#
        let decoded = try JSONDecoder().decode(SYSAssetManifest.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertNil(decoded.items[0].sha256)
        XCTAssertNil(decoded.items[0].required)
    }

    func testProgressFractionUsesBytesWhenKnown() {
        let progress = SYSAssetProgress(completedPacks: 1, totalPacks: 4,
                                        bytesDownloaded: 30, totalBytes: 120)
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
    }

    func testProgressFractionFallsBackToPackCount() {
        // A manifest without byte counts must still produce a sane bar.
        let progress = SYSAssetProgress(completedPacks: 2, totalPacks: 4,
                                        bytesDownloaded: 0, totalBytes: 0)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
    }

    func testProgressFractionIsZeroWhenNothingToDo() {
        let progress = SYSAssetProgress(completedPacks: 0, totalPacks: 0,
                                        bytesDownloaded: 0, totalBytes: 0)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testUnconfiguredFailsClosed() async {
        let assets = SYSAssets()
        let result = await assets.prepareRequired()
        guard case let .failure(error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notConfigured)
    }

    func testLocalURLUsesContentAddressedFilename() async throws {
        let assets = SYSAssets()
        await assets.configure(baseURL: URL(string: "https://example.test")!)
        let pack = SYSAssetPack(id: "a", bundle: "/packs/a-deadbeef.json")
        let url = try await assets.localURL(for: pack)
        XCTAssertEqual(url.lastPathComponent, "a-deadbeef.json")
    }

    func testErrorsAreDistinguishable() {
        // The app branches on these to decide whether to offer a retry button.
        XCTAssertNotEqual(SYSAssetsError.offline, .server(status: 500))
        XCTAssertNotEqual(SYSAssetsError.corrupt(pack: "a"), .corrupt(pack: "b"))
        XCTAssertEqual(SYSAssetsError.unsupportedManifest(version: 2), .unsupportedManifest(version: 2))
    }
}

// MARK: - SYSAssets handler logic centralised from the app

final class SYSAssetsHandlerTests: XCTestCase {
    func testRetryIsOfferedOnlyWhenItCouldHelp() {
        // Offering "try again" for a fault the server has to fix teaches people
        // to tap it forever.
        XCTAssertTrue(SYSAssetsError.offline.isRetryable)
        XCTAssertTrue(SYSAssetsError.server(status: 500).isRetryable)
        XCTAssertTrue(SYSAssetsError.server(status: 503).isRetryable)

        XCTAssertFalse(SYSAssetsError.server(status: 404).isRetryable)
        XCTAssertFalse(SYSAssetsError.server(status: 403).isRetryable)
        XCTAssertFalse(SYSAssetsError.corrupt(pack: "a").isRetryable)
        XCTAssertFalse(SYSAssetsError.unsupportedManifest(version: 2).isRetryable)
        XCTAssertFalse(SYSAssetsError.notConfigured.isRetryable)
    }

    func testOnlyAStaleBuildAsksForAnUpdate() {
        XCTAssertTrue(SYSAssetsError.unsupportedManifest(version: 9).requiresAppUpdate)
        XCTAssertFalse(SYSAssetsError.offline.requiresAppUpdate)
        XCTAssertFalse(SYSAssetsError.corrupt(pack: "a").requiresAppUpdate)
    }

    func testRetryableAndUpdateAreMutuallyExclusive() {
        // A screen shows one or the other; an error that claims both would render
        // a retry button next to "please update".
        let all: [SYSAssetsError] = [
            .offline, .server(status: 500), .server(status: 404),
            .corrupt(pack: "a"), .unreadableManifest("x"),
            .unsupportedManifest(version: 2), .missingRequiredPack(id: "a"), .notConfigured,
        ]
        for error in all {
            XCTAssertFalse(error.isRetryable && error.requiresAppUpdate, "\(error)")
        }
    }

    func testCachedPacksIsEmptyWithoutAManifest() async {
        let assets = SYSAssets()
        let cached = await assets.cachedPacks()
        XCTAssertTrue(cached.isEmpty)
    }
}

// MARK: - Typed pack and config access

private struct TestPack: Decodable, Equatable, Sendable {
    let id: String
    let items: [String]
}

private struct TestAppConfig: Decodable, Equatable {
    let maxPages: Int
    let seasonal: Bool
    let nested: Nested
    struct Nested: Decodable, Equatable { let name: String; let sizes: [Int] }
}

final class SYSTypedAccessTests: XCTestCase {
    private func decode(_ json: String) throws -> SYSConfigData {
        try JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8))
    }

    func testStoreStartsEmptyAndForgetsCleanly() async {
        let store = SYSAssetStore<TestPack>()
        let empty = await store.all()
        XCTAssertTrue(empty.isEmpty)

        let loaded = await store.loaded("a")
        XCTAssertNil(loaded)

        let isLoaded = await store.isLoaded("a")
        XCTAssertFalse(isLoaded)

        await store.forgetAll()
        let count = await store.count
        XCTAssertEqual(count, 0)
    }

    func testStoreFailsClosedWhenAssetsAreUnconfigured() async {
        // An app must not get a half-built store back; it has to see the failure.
        let store = SYSAssetStore<TestPack>(assets: SYSAssets())
        let result = await store.pack("a")
        guard case let .failure(error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notConfigured)
    }

    func testDecodeFailureIsNotRetryable() {
        // The bytes are what the server published — asking again returns them
        // again, so a retry button here would lie.
        XCTAssertFalse(SYSAssetsError.decoding("x").isRetryable)
        XCTAssertFalse(SYSAssetsError.decoding("x").requiresAppUpdate)
    }

    func testAppConfigDecodesIntoTheAppsOwnType() throws {
        // Nested objects and arrays must survive the SYSValue round-trip; if they
        // did not, apps would silently fall back to defaults for half their
        // settings and nothing would say why.
        let config = try decode("""
        {"configVersion":1,"app":{"maxPages":12,"seasonal":true,
         "nested":{"name":"winter","sizes":[1,2,3]}}}
        """)
        XCTAssertEqual(config.app(as: TestAppConfig.self), TestAppConfig(
            maxPages: 12, seasonal: true,
            nested: .init(name: "winter", sizes: [1, 2, 3])
        ))
    }

    func testAppConfigReturnsNilRatherThanFailingOnMismatch() throws {
        let config = try decode(#"{"configVersion":1,"app":{"maxPages":"not a number"}}"#)
        XCTAssertNil(config.app(as: TestAppConfig.self))
    }

    func testAppConfigIsNilWhenSectionAbsent() throws {
        let config = try decode(#"{"configVersion":1}"#)
        XCTAssertNil(config.app(as: TestAppConfig.self))
    }
}
