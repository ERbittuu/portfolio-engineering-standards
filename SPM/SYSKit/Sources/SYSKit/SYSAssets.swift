import Foundation

/// One downloadable pack of content, as named by the manifest.
public struct SYSAssetPack: Codable, Equatable, Sendable {
    public let id: String
    public let title: String?
    /// Site-relative path, e.g. `/packs/seaworld-3446a234.json`.
    public let bundle: String
    public let bytes: Int?
    /// Hex SHA-256 of the pack bytes. Checked before a pack is accepted.
    public let sha256: String?
    /// Packs the app cannot start without. Absent means false.
    public let required: Bool?

    public init(id: String, title: String? = nil, bundle: String,
                bytes: Int? = nil, sha256: String? = nil, required: Bool? = nil) {
        self.id = id
        self.title = title
        self.bundle = bundle
        self.bytes = bytes
        self.sha256 = sha256
        self.required = required
    }
}

/// The index of everything the site hosts for this app.
public struct SYSAssetManifest: Codable, Equatable, Sendable {
    public let manifestVersion: Int
    public let generatedAt: String?
    public let items: [SYSAssetPack]

    public init(manifestVersion: Int, generatedAt: String? = nil, items: [SYSAssetPack]) {
        self.manifestVersion = manifestVersion
        self.generatedAt = generatedAt
        self.items = items
    }
}

/// Why content could not be made available.
///
/// Separated by what the user can do about it: `offline` is worth a retry button,
/// `corrupt` will fail identically until the server is fixed, and
/// `unsupportedManifest` means this build is too old to read what is being served.
public enum SYSAssetsError: Error, Equatable, Sendable {
    /// No usable network. Retrying is the right offer.
    case offline
    /// The server answered, and the answer was a failure.
    case server(status: Int)
    /// Downloaded bytes did not match the hash the manifest published.
    case corrupt(pack: String)
    /// The manifest could not be read.
    case unreadableManifest(String)
    /// The manifest is a newer format than this build understands.
    case unsupportedManifest(version: Int)
    /// A required pack is not in the manifest at all.
    case missingRequiredPack(id: String)
    /// `configure` was never called.
    case notConfigured
}

/// Progress through a `prepareRequired` run, for apps that show a bar.
public struct SYSAssetProgress: Equatable, Sendable {
    public let completedPacks: Int
    public let totalPacks: Int
    public let bytesDownloaded: Int
    public let totalBytes: Int

    public var fraction: Double {
        totalBytes > 0
            ? Double(bytesDownloaded) / Double(totalBytes)
            : (totalPacks > 0 ? Double(completedPacks) / Double(totalPacks) : 0)
    }
}

/// Downloads and caches the content an app ships separately from its binary.
///
/// Apps that keep artwork out of the bundle need the same four things every time:
/// fetch an index, download what is required before the first screen, verify it,
/// and keep it for next launch. Doing that once here means an app writes screens,
/// not a download manager.
///
/// Like the rest of SYSKit this renders nothing. `prepareRequired` returns a
/// result; the app decides whether that becomes a spinner, an error screen, or a
/// retry button. `SYSBootstrap` folds it into startup for apps that want the
/// standard sequence.
///
/// Everything is cached in Application Support, which is backed up and not
/// evictable under storage pressure — losing content mid-flight on a device with
/// a full disk would strand an app that cannot render without it. Downloads are
/// written to a temporary file and moved into place only after the hash matches,
/// so an interrupted download can never be mistaken for a complete one.
public actor SYSAssets {
    public static let shared = SYSAssets()

    /// Highest manifest format this build understands.
    public static let supportedManifestVersion = 1

    private let network: SYSNetwork
    private let fileManager: FileManager

    private var baseURL: URL?
    private var explicitRequired: [String] = []
    private var cachedManifest: SYSAssetManifest?
    private var manifestETag: String?

    /// Attempts per pack before giving up, with a short backoff between them.
    /// The app's retry button is the real recovery path; this only rides out a
    /// blip so a single dropped packet does not become an error screen.
    public var attemptsPerPack: Int = 3
    public var retryBackoff: TimeInterval = 1.5

    public init(network: SYSNetwork = .shared, fileManager: FileManager = .default) {
        self.network = network
        self.fileManager = fileManager
    }

    // MARK: Configuration

    /// - Parameters:
    ///   - baseURL: site root, e.g. `https://myapp.web.app`.
    ///   - required: pack ids the app cannot start without. Leave empty to rely
    ///     on the manifest's own `required` flags.
    public func configure(baseURL: URL, required: [String] = []) {
        self.baseURL = baseURL
        self.explicitRequired = required
    }

    public var manifest: SYSAssetManifest? { cachedManifest }

    // MARK: Cache locations

    /// Where packs live. Created on demand.
    public func cacheDirectory() throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: true)
        let directory = support.appendingPathComponent("SYSAssets", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Content is re-downloadable; excluding it keeps iCloud backups small.
            var mutable = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            try? mutable.setResourceValues(values)
        }
        return directory
    }

    /// Local file for a pack, whether or not it exists yet.
    ///
    /// Named after the remote filename, which carries the content hash — so a new
    /// version of a pack lands beside the old one rather than overwriting it, and
    /// a half-written new copy can never be mistaken for the good old one.
    public func localURL(for pack: SYSAssetPack) throws -> URL {
        let name = (pack.bundle as NSString).lastPathComponent
        return try cacheDirectory().appendingPathComponent(name)
    }

    public func isCached(_ pack: SYSAssetPack) -> Bool {
        guard let url = try? localURL(for: pack) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// Bytes of a cached pack, or nil if it is not downloaded.
    public func cachedData(for pack: SYSAssetPack) -> Data? {
        guard let url = try? localURL(for: pack) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: Manifest

    @discardableResult
    public func refreshManifest() async -> Result<SYSAssetManifest, SYSAssetsError> {
        guard let baseURL else { return .failure(.notConfigured) }
        let url = baseURL.appendingPathComponent("manifest.json")

        do {
            let (value, etag) = try await network.get(url, as: SYSAssetManifest.self, etag: manifestETag)
            guard value.manifestVersion <= Self.supportedManifestVersion else {
                // Reading a newer format by guessing is how you ship a crash to
                // the installs you can least afford to break.
                SYSLogger.error("assets: manifest v\(value.manifestVersion) is newer than supported v\(Self.supportedManifestVersion)")
                return .failure(.unsupportedManifest(version: value.manifestVersion))
            }
            cachedManifest = value
            manifestETag = etag
            persistManifest(value)
            return .success(value)
        } catch SYSNetworkError.notModified {
            if let cachedManifest { return .success(cachedManifest) }
            if let restored = loadPersistedManifest() {
                cachedManifest = restored
                return .success(restored)
            }
            return .failure(.unreadableManifest("304 with nothing cached"))
        } catch SYSNetworkError.offline {
            if let restored = cachedManifest ?? loadPersistedManifest() {
                // Offline with a manifest from last launch is a working app, not
                // an error — cached packs still resolve.
                cachedManifest = restored
                return .success(restored)
            }
            return .failure(.offline)
        } catch let SYSNetworkError.http(status) {
            return .failure(.server(status: status))
        } catch let SYSNetworkError.decoding(detail) {
            return .failure(.unreadableManifest(detail))
        } catch {
            return .failure(.offline)
        }
    }

    private var persistedManifestURL: URL? {
        try? cacheDirectory().appendingPathComponent("manifest.json")
    }

    private func persistManifest(_ manifest: SYSAssetManifest) {
        guard let url = persistedManifestURL,
              let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadPersistedManifest() -> SYSAssetManifest? {
        guard let url = persistedManifestURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SYSAssetManifest.self, from: data)
    }

    // MARK: Downloading

    /// Makes every required pack available locally.
    ///
    /// Safe to call again — already-cached packs are skipped, so an app's retry
    /// button costs only what is actually still missing.
    @discardableResult
    public func prepareRequired(
        progress: (@Sendable (SYSAssetProgress) -> Void)? = nil
    ) async -> Result<Void, SYSAssetsError> {
        let manifestResult = await refreshManifest()
        guard case let .success(manifest) = manifestResult else {
            if case let .failure(error) = manifestResult { return .failure(error) }
            return .failure(.notConfigured)
        }

        let wanted = requiredPacks(in: manifest)
        if let missing = explicitRequired.first(where: { id in !manifest.items.contains { $0.id == id } }) {
            return .failure(.missingRequiredPack(id: missing))
        }

        let outstanding = wanted.filter { !isCached($0) }
        let totalBytes = outstanding.reduce(0) { $0 + ($1.bytes ?? 0) }
        var downloaded = 0
        var completed = wanted.count - outstanding.count

        progress?(SYSAssetProgress(completedPacks: completed,
                                   totalPacks: wanted.count,
                                   bytesDownloaded: 0,
                                   totalBytes: totalBytes))

        for pack in outstanding {
            switch await fetch(pack) {
            case .success:
                completed += 1
                downloaded += pack.bytes ?? 0
                progress?(SYSAssetProgress(completedPacks: completed,
                                           totalPacks: wanted.count,
                                           bytesDownloaded: downloaded,
                                           totalBytes: totalBytes))
            case let .failure(error):
                SYSLogger.error("assets: required pack \(pack.id) failed — \(error)")
                return .failure(error)
            }
        }

        SYSLogger.info("assets: \(wanted.count) required pack(s) ready")
        return .success(())
    }

    /// Makes one pack available, downloading it if needed. For content fetched
    /// on demand rather than at startup.
    @discardableResult
    public func ensure(_ packID: String) async -> Result<Data, SYSAssetsError> {
        guard let manifest = cachedManifest ?? loadPersistedManifest() else {
            let refreshed = await refreshManifest()
            guard case .success = refreshed else {
                if case let .failure(error) = refreshed { return .failure(error) }
                return .failure(.notConfigured)
            }
            return await ensure(packID)
        }
        guard let pack = manifest.items.first(where: { $0.id == packID }) else {
            return .failure(.missingRequiredPack(id: packID))
        }
        if let data = cachedData(for: pack) { return .success(data) }
        switch await fetch(pack) {
        case .success(let data): return .success(data)
        case .failure(let error): return .failure(error)
        }
    }

    private func requiredPacks(in manifest: SYSAssetManifest) -> [SYSAssetPack] {
        if !explicitRequired.isEmpty {
            return manifest.items.filter { explicitRequired.contains($0.id) }
        }
        return manifest.items.filter { $0.required == true }
    }

    private func fetch(_ pack: SYSAssetPack) async -> Result<Data, SYSAssetsError> {
        guard let baseURL else { return .failure(.notConfigured) }
        let url = baseURL.appendingPathComponent(pack.bundle)

        var lastError: SYSAssetsError = .offline
        for attempt in 1 ... max(1, attemptsPerPack) {
            do {
                let (data, _) = try await network.data(url, timeout: 60)

                if let expected = pack.sha256 {
                    let actual = SYSHash.sha256Hex(data)
                    guard actual == expected.lowercased() else {
                        // Retrying a hash mismatch just re-downloads the same bad
                        // bytes; the server is wrong, not the connection.
                        SYSLogger.error("assets: \(pack.id) hash mismatch — expected \(expected.prefix(8)), got \(actual.prefix(8))")
                        return .failure(.corrupt(pack: pack.id))
                    }
                }

                do {
                    try writeAtomically(data, for: pack)
                } catch {
                    SYSLogger.error("assets: could not store \(pack.id) — \(error)")
                }
                return .success(data)
            } catch SYSNetworkError.offline {
                lastError = .offline
            } catch let SYSNetworkError.http(status) {
                lastError = .server(status: status)
                // 4xx will answer the same way next time.
                if (400 ..< 500).contains(status) { return .failure(lastError) }
            } catch {
                lastError = .offline
            }

            if attempt < attemptsPerPack {
                try? await Task.sleep(nanoseconds: UInt64(retryBackoff * Double(attempt) * 1_000_000_000))
            }
        }
        return .failure(lastError)
    }

    /// Writes to a sibling temporary file, then moves it into place, so a process
    /// killed mid-write leaves the old pack intact rather than a truncated one.
    private func writeAtomically(_ data: Data, for pack: SYSAssetPack) throws {
        let destination = try localURL(for: pack)
        try data.write(to: destination, options: .atomic)
    }

    // MARK: Housekeeping

    /// Deletes cached packs the manifest no longer names.
    ///
    /// Content-addressed filenames mean a replaced pack leaves its predecessor
    /// behind forever otherwise.
    @discardableResult
    public func pruneStalePacks() -> Int {
        guard let manifest = cachedManifest ?? loadPersistedManifest(),
              let directory = try? cacheDirectory(),
              let entries = try? fileManager.contentsOfDirectory(atPath: directory.path)
        else { return 0 }

        let live = Set(manifest.items.map { ($0.bundle as NSString).lastPathComponent } + ["manifest.json"])
        var removed = 0
        for entry in entries where !live.contains(entry) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(entry))
            removed += 1
        }
        if removed > 0 { SYSLogger.info("assets: pruned \(removed) stale pack(s)") }
        return removed
    }

    /// Removes everything. For a "clear downloaded content" setting.
    public func clearCache() {
        guard let directory = try? cacheDirectory() else { return }
        try? fileManager.removeItem(at: directory)
        cachedManifest = nil
        manifestETag = nil
    }
}
