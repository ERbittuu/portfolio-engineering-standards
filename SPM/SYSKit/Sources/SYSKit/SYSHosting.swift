import Foundation

/// Where this app's hosted files live, worked out rather than configured.
///
/// Every app was passing the same string to two places — the config URL and the
/// assets base URL — and that string is not independent information: Firebase
/// Hosting serves a project at `https://<PROJECT_ID>.web.app`, and `PROJECT_ID`
/// is already in the `GoogleService-Info.plist` the app ships. Repeating it in
/// Swift means it can be wrong, and a typo there points a release at another
/// project's content.
///
/// Reads the plist with Foundation only. It is Firebase's file, but no Firebase
/// code is involved, so this stays in SYSKit rather than the SYSFirebase adapter
/// — `SYSConfig` and `SYSAssets` both need it and neither can depend on Firebase.
///
/// Apps on a custom domain call `setSiteURL(_:)` before startup; everything else
/// gets it for free.
public enum SYSHosting {
    private static var override: URL?
    private static var cachedProjectID: String??

    /// Point every hosted lookup somewhere else — a custom domain, or a staging
    /// site. Call before `SYSBootstrap.start`.
    public static func setSiteURL(_ url: URL?) {
        override = url
    }

    /// `PROJECT_ID` from GoogleService-Info.plist, or nil if the app ships none.
    public static func projectID(bundle: Bundle = .main) -> String? {
        if let cached = cachedProjectID { return cached }

        // Resources may be flattened into the bundle root depending on how they
        // are grouped, so look up by name rather than by path.
        let value: String? = {
            guard let url = bundle.url(forResource: "GoogleService-Info", withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = plist as? [String: Any],
                  let id = dictionary["PROJECT_ID"] as? String,
                  !id.isEmpty
            else { return nil }
            return id
        }()

        cachedProjectID = value
        if value == nil {
            SYSLogger.info("hosting: no PROJECT_ID in GoogleService-Info.plist — set the site URL explicitly")
        }
        return value
    }

    /// The site root, e.g. `https://myapp-prod.web.app`.
    public static func siteURL(bundle: Bundle = .main) -> URL? {
        if let override { return override }
        guard let id = projectID(bundle: bundle) else { return nil }
        return URL(string: "https://\(id).web.app")
    }

    /// The config file every app serves from its own site.
    public static func configURL(bundle: Bundle = .main) -> URL? {
        siteURL(bundle: bundle)?.appendingPathComponent("config.json")
    }

    /// Testing seam: forget what was read so a different bundle can be used.
    public static func resetForTesting() {
        override = nil
        cachedProjectID = nil
    }
}
