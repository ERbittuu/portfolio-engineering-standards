import Foundation

// MARK: - Localised text

/// A string that may be provided per language: `{"en": "...", "hi": "..."}`.
///
/// Also accepts a bare string, so a single-locale app can write
/// `"message": "text"` and expand it later without breaking older builds.
public struct SYSLocalizedText: Codable {
    private var values: [String: String]

    public init(_ values: [String: String]) { self.values = values }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = ["en": single]
        } else {
            values = (try? container.decode([String: String].self)) ?? [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    /// Best match for the device language, falling back to English, then to
    /// whatever exists. Never nil when any text was provided.
    public func resolved(for locales: [String] = Locale.preferredLanguages) -> String? {
        for locale in locales {
            if let match = values[String(locale.prefix(2))] { return match }
        }
        return values["en"] ?? values.values.first
    }
}

// MARK: - Value

/// Minimal type-erased JSON value, so the `app` object can hold mixed types
/// without pulling in a dependency.
public enum SYSValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool)
    case array([SYSValue]), object([String: SYSValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([SYSValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: SYSValue].self) { self = .object(value); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    public var intValue: Int? { if case .int(let value) = self { return value }; return nil }
    public var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var doubleValue: Double? { if case .double(let value) = self { return value }; return nil }
}

// MARK: - Model

/// The shape of `config.json`. Everything except `app` is standard across apps.
///
/// Every field is optional on purpose: a config missing a key must degrade to a
/// sensible default, never fail to decode. A config that fails to decode is a
/// config that can no longer be fixed remotely.
public struct SYSConfigData: Codable {
    public struct Update: Codable {
        /// Below this the app must not be usable. See `SYSUpdate`.
        public var minimumVersion: String?
        /// Below this, nudge — but let the user continue.
        public var recommendedVersion: String?
        public var message: SYSLocalizedText?
    }

    public struct Maintenance: Codable {
        public var enabled: Bool?
        public var message: SYSLocalizedText?
    }

    public struct Rating: Codable {
        public var minSessions: Int?
        public var minDaysSinceInstall: Int?
    }

    /// Where remote content lives, for apps shipping content packs.
    public struct Content: Codable {
        public var baseURL: String?
        public var manifestPath: String?
    }

    /// Promotes the studio's other apps without shipping a build.
    public struct CrossPromo: Codable {
        public struct Item: Codable {
            public var bundleId: String?
            public var name: String?
            public var iconURL: String?
            public var storeURL: String?
        }
        public var enabled: Bool?
        public var apps: [Item]?
    }

    public var configVersion: Int?
    public var updatedAt: String?
    public var update: Update?
    public var maintenance: Maintenance?
    public var flags: [String: Bool]?
    public var rating: Rating?
    public var urls: [String: String]?
    public var content: Content?
    public var crossPromo: CrossPromo?
    /// Release notes per version: `{"2.5.0": {"en": ["…"]}}`.
    public var whatsNew: [String: [String: [String]]]?
    /// App-specific values, so apps differ without forking this package.
    public var app: [String: SYSValue]?

    public init() {}

    /// The `app` section decoded into a type the app defines.
    ///
    /// Lives here rather than on the manager so it can be exercised against a
    /// decoded config directly, with no launch, no disk and no network.
    public func app<T: Decodable>(as type: T.Type) -> T? {
        guard let section = app else { return nil }
        do {
            // SYSValue is Codable and models nested objects, arrays and null, so
            // this round-trip is lossless — no need to retain the raw JSON.
            let json = try JSONEncoder().encode(section)
            return try JSONDecoder().decode(type, from: json)
        } catch {
            SYSLogger.error("config: app section did not decode as \(type) — \(error)")
            return nil
        }
    }
}

// MARK: - Manager

/// Loads config at launch, serves it synchronously, refreshes in the background.
///
/// Sources in order of preference: a cached copy from a previous fetch, the copy
/// bundled with the app, then empty defaults. It can never end up worse than
/// what shipped.
///
/// A fetched config normally applies on the **next** launch, so values stay
/// stable for a whole session. `SYSBootstrap` is the one exception: it waits
/// briefly for a refresh before evaluating the maintenance and force-update
/// gates, because a kill switch that needs a relaunch is not a kill switch.
public final class SYSConfig {
    public static let shared = SYSConfig()

    public private(set) var data = SYSConfigData()

    private let bundle: Bundle
    private let network: SYSNetwork
    private let fileManager: FileManager
    private var remoteURL: URL?

    private static let fileName = "config.json"
    private static let etagKey = SYSSettingsKey<String?>("sys.config.etag", default: nil)

    public init(
        bundle: Bundle = .main,
        network: SYSNetwork = .shared,
        fileManager: FileManager = .default,
        remoteURL: URL? = nil
    ) {
        self.bundle = bundle
        self.network = network
        self.fileManager = fileManager
        self.remoteURL = remoteURL
    }

    /// Where to fetch from. Usually derived from the app's Firebase Hosting.
    public func setRemoteURL(_ url: URL?) { remoteURL = url }

    /// Injects config directly, bypassing bundle and cache. Tests only.
    func applyForTesting(_ data: SYSConfigData) { self.data = data }

    // MARK: Lifecycle

    /// Call once, as early as possible at launch, before anything reads a value.
    /// Synchronous and local — no network — so it cannot delay startup.
    public func load() {
        let bundled = decode(bundledData())
        let cached = decode(cachedData())

        // Prefer the cache only if genuinely newer. A cache written before this
        // build shipped is stale relative to the bundled copy.
        if let cached, (cached.configVersion ?? 0) >= (bundled?.configVersion ?? 0) {
            data = cached
        } else if let bundled {
            data = bundled
        }
    }

    /// Fetches and stores for next launch. Returns true when newer config was
    /// applied. Failures are silent by design — offline is normal.
    @discardableResult
    public func refresh() async -> Bool {
        // Not configured means "the usual place", not "no remote config". The
        // URL is derivable from the Firebase project the app already ships, so
        // requiring every app to pass it only creates a way to get it wrong.
        guard let remoteURL = remoteURL ?? SYSHosting.configURL(bundle: bundle) else { return false }

        do {
            let etag = SYSSettings.shared[Self.etagKey]
            let (payload, newETag) = try await network.data(remoteURL, etag: etag)
            guard let fetched = decode(payload) else { return false }

            // Never accept something older — a stale CDN copy would otherwise
            // roll the app backwards.
            guard (fetched.configVersion ?? 0) >= (data.configVersion ?? 0) else { return false }

            try? payload.write(to: cacheURL, options: .atomic)
            SYSSettings.shared[Self.etagKey] = newETag
            data = fetched
            return true
        } catch SYSNetworkError.notModified {
            return false
        } catch {
            SYSLogger.debug("config refresh failed: \(error)")
            return false
        }
    }

    // MARK: Accessors

    public func flag(_ key: String, default fallback: Bool = false) -> Bool {
        data.flags?[key] ?? fallback
    }

    public func url(_ key: String) -> URL? {
        data.urls?[key].flatMap(URL.init(string:))
    }

    /// Other apps to promote, excluding this one. Empty when disabled, so
    /// callers need no extra check.
    public var crossPromoApps: [SYSConfigData.CrossPromo.Item] {
        guard data.crossPromo?.enabled == true else { return [] }
        return (data.crossPromo?.apps ?? []).filter { $0.bundleId != bundle.bundleIdentifier }
    }

    /// App-specific value from the `app` object.
    public func value(_ key: String) -> SYSValue? { data.app?[key] }

    /// The `app` section decoded into a type the app defines.
    ///
    /// `value("someKey")?.intValue` works, but every app ends up writing the same
    /// unwrapping by hand and a typo in a key is a silent nil rather than a
    /// compile error. Declaring the shape once and decoding into it moves that
    /// mistake to build time:
    ///
    /// ```swift
    /// struct ColorfulConfig: Decodable {
    ///     let maxRecentPages: Int
    ///     let showSeasonalPack: Bool
    /// }
    /// let tuning = SYSConfig.shared.app(as: ColorfulConfig.self)
    /// ```
    ///
    /// Returns nil if the section is absent or does not match the type, and logs
    /// why — a config the app cannot read must not be worse than no config at
    /// all, so the caller falls back to its own defaults rather than failing.
    ///
    /// Decoded on each call, with the same liveness as `value(_:)`. The section is
    /// small, but hold the result rather than calling it from a view body.
    public func app<T: Decodable>(as type: T.Type) -> T? { data.app(as: type) }

    public var currentVersion: String { SYSVersion.current(bundle: bundle) }

    // MARK: Storage

    /// Application Support, not Caches: the system can purge Caches, which would
    /// silently roll a user back to the bundled config after a remote change.
    private var cacheURL: URL {
        let directory = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return directory.appendingPathComponent(Self.fileName)
    }

    private func cachedData() -> Data? { try? Data(contentsOf: cacheURL) }

    private func bundledData() -> Data? {
        bundle.url(forResource: "config", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
    }

    private func decode(_ payload: Data?) -> SYSConfigData? {
        payload.flatMap { try? JSONDecoder().decode(SYSConfigData.self, from: $0) }
    }
}
