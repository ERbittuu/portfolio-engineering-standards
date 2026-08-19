//
//  SYSConfig.swift
//  {{PROJECT_NAME}}
//
//  PES standard remote config — identical in every app.
//
//  Do not fork this file per app. App-specific values belong under the `app`
//  key in config.json and are read with SYSConfig.shared.value(_:). If an app
//  already has its own config loader, replace it with this one rather than
//  running both — two sources of truth for "is this flag on" is exactly the
//  bug this exists to prevent.
//

import Foundation

// MARK: - Localised text

/// A string that may be provided per language: `{"en": "...", "hi": "..."}`.
///
/// Also accepts a bare string, so a single-locale app can write
/// `"message": "text"` and a multi-locale one can expand it later without
/// breaking older builds.
struct SYSLocalizedText: Codable {
    private var values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = ["en": single]
        } else {
            values = (try? container.decode([String: String].self)) ?? [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    /// Best match for the device language, falling back to English, then to
    /// whatever exists. Never returns nil when any text was provided.
    func resolved(for locales: [String] = Locale.preferredLanguages) -> String? {
        for locale in locales {
            let code = String(locale.prefix(2))
            if let match = values[code] { return match }
        }
        return values["en"] ?? values.values.first
    }
}

// MARK: - Model

/// The shape of `config.json`. Everything except `app` is standard across apps.
///
/// Every field is optional on purpose: a config missing a key must degrade to a
/// sensible default, never fail to decode. A config that fails to decode is a
/// config that can no longer be fixed remotely.
struct SYSConfigData: Codable {
    struct Update: Codable {
        /// Below this, the app must not be usable. See `isUpdateRequired`.
        var minimumVersion: String?
        /// Below this, nudge — but let the user continue.
        var recommendedVersion: String?
        var message: SYSLocalizedText?
    }

    struct Maintenance: Codable {
        var enabled: Bool?
        var message: SYSLocalizedText?
    }

    struct Rating: Codable {
        var minSessions: Int?
        var minDaysSinceInstall: Int?
    }

    /// Where remote content lives, for apps that ship content packs.
    struct Content: Codable {
        var baseURL: String?
        var manifestPath: String?
    }

    /// Promotes the studio's other apps without shipping a build. Ordering is
    /// the server's; the app renders the list as given.
    struct CrossPromo: Codable {
        struct Item: Codable {
            var bundleId: String?
            var name: String?
            var iconURL: String?
            var storeURL: String?
        }
        var enabled: Bool?
        var apps: [Item]?
    }

    var configVersion: Int?
    var updatedAt: String?
    var update: Update?
    var maintenance: Maintenance?
    var flags: [String: Bool]?
    var rating: Rating?
    var urls: [String: String]?
    var content: Content?
    var crossPromo: CrossPromo?
    /// App-specific values. Free-form so apps differ without forking this file.
    var app: [String: SYSValue]?
}

/// Minimal type-erased JSON value, so `app` can hold mixed types without
/// pulling in a dependency.
enum SYSValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool)
    case array([SYSValue]), object([String: SYSValue]), null

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value):    try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value):   try container.encode(value)
        case .array(let value):  try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null:              try container.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var intValue: Int?       { if case .int(let v) = self { return v }; return nil }
    var boolValue: Bool?     { if case .bool(let v) = self { return v }; return nil }
    var doubleValue: Double? { if case .double(let v) = self { return v }; return nil }
}

// MARK: - Manager

/// Loads config at launch, serves it synchronously, refreshes in the background
/// for next launch.
///
/// Sources in order of preference: a cached copy from a previous fetch, the copy
/// bundled with the app, then empty defaults. It can never end up worse than
/// what shipped.
///
/// A fetched config applies on the **next** launch, never mid-session, so values
/// stay stable for a whole session and nothing changes under the user while they
/// are using the app.
final class SYSConfig {
    static let shared = SYSConfig()

    private(set) var data = SYSConfigData()

    private let session: URLSession
    private let bundle: Bundle
    private let remoteURL: URL?

    private static let fileName = "config.json"

    init(
        bundle: Bundle = .main,
        session: URLSession = .shared,
        remoteURL: URL? = URL(string: "{{CONFIG_URL}}")
    ) {
        self.bundle = bundle
        self.session = session
        self.remoteURL = remoteURL
    }

    // MARK: Lifecycle

    /// Call once, as early as possible at launch, before anything reads a value.
    /// Synchronous and local — no network — so it cannot delay startup.
    func load() {
        let bundled = decode(bundledData())
        let cached = decode(cachedData())

        // Prefer the cache only if it is genuinely newer. A cache written before
        // this build shipped is stale relative to the bundled copy.
        if let cached, (cached.configVersion ?? 0) >= (bundled?.configVersion ?? 0) {
            data = cached
        } else if let bundled {
            data = bundled
        }
    }

    /// Fetches in the background and stores the result for next launch. Safe to
    /// call on every launch; failures are silent by design.
    func refresh(completion: (() -> Void)? = nil) {
        guard let remoteURL else { completion?(); return }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        session.dataTask(with: request) { [weak self] payload, response, _ in
            defer { completion?() }
            guard let self,
                  let payload,
                  let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  let fetched = self.decode(payload)
            else { return }

            // Never cache something older than what we already have — a stale CDN
            // copy would otherwise roll the app backwards.
            guard (fetched.configVersion ?? 0) >= (self.data.configVersion ?? 0) else { return }

            try? payload.write(to: self.cacheURL, options: .atomic)
        }.resume()
    }

    // MARK: Standard accessors

    /// True when the running version is older than `update.minimumVersion`.
    /// The blocking UI belongs to each app — this only answers the question.
    var isUpdateRequired: Bool {
        guard let minimum = data.update?.minimumVersion else { return false }
        return Self.compare(currentVersion, minimum) == .orderedAscending
    }

    /// True when a newer version is worth nudging about, but not blocking.
    var isUpdateRecommended: Bool {
        guard let recommended = data.update?.recommendedVersion else { return false }
        return Self.compare(currentVersion, recommended) == .orderedAscending
    }

    var updateMessage: String? { data.update?.message?.resolved() }

    var isUnderMaintenance: Bool { data.maintenance?.enabled == true }
    var maintenanceMessage: String? { data.maintenance?.message?.resolved() }

    func flag(_ key: String, default fallback: Bool = false) -> Bool {
        data.flags?[key] ?? fallback
    }

    func url(_ key: String) -> URL? {
        data.urls?[key].flatMap(URL.init(string:))
    }

    /// Other apps to promote. Empty when disabled, so callers need no extra check.
    var crossPromoApps: [SYSConfigData.CrossPromo.Item] {
        guard data.crossPromo?.enabled == true else { return [] }
        return (data.crossPromo?.apps ?? []).filter { $0.bundleId != Bundle.main.bundleIdentifier }
    }

    /// App-specific value from the `app` object.
    func value(_ key: String) -> SYSValue? { data.app?[key] }

    var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Version comparison

    /// Compares dotted numeric versions numerically.
    ///
    /// String comparison gets this wrong — it sorts "1.10.0" *below* "1.9.0",
    /// which works fine for years and then breaks at the first double-digit
    /// minor. Missing components count as zero, so "1.2" == "1.2.0".
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(left.count, right.count) {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart < rightPart { return .orderedAscending }
            if leftPart > rightPart { return .orderedDescending }
        }
        return .orderedSame
    }

    // MARK: Storage

    /// Application Support, not Caches: the system can purge Caches, which would
    /// silently roll a user back to the bundled config after a remote change.
    private var cacheURL: URL {
        let directory = (try? FileManager.default.url(
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
