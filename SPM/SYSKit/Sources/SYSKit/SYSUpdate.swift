import Foundation

/// Whether the running version is still acceptable.
///
/// Answers the question only — the blocking screen belongs to each app, because
/// a colouring app and a prayer app should not share one. PES standardises the
/// decision and the version comparison, which are the parts that are easy to
/// get wrong.
public enum SYSUpdateStatus: Equatable {
    case none
    /// A newer version exists; nudge, but let the user continue.
    case recommended
    /// Below the minimum. The app must not be usable.
    case required
}

public enum SYSUpdate {
    public static var status: SYSUpdateStatus { status(config: .shared) }

    public static func status(config: SYSConfig) -> SYSUpdateStatus {
        let current = config.currentVersion

        if let minimum = config.data.update?.minimumVersion,
           SYSVersion.isOlder(current, than: minimum) {
            return .required
        }
        if let recommended = config.data.update?.recommendedVersion,
           SYSVersion.isOlder(current, than: recommended) {
            return .recommended
        }
        return .none
    }

    /// Localised message for whichever status applies.
    public static func message(config: SYSConfig = .shared) -> String? {
        config.data.update?.message?.resolved()
    }

    /// Where to send the user to update. Set `urls.appStore` in config.
    public static func storeURL(config: SYSConfig = .shared) -> URL? {
        config.url("appStore")
    }
}

/// The kill switch. Config alone does nothing — this is what reads it.
public enum SYSMaintenance {
    public static func isActive(config: SYSConfig = .shared) -> Bool {
        config.data.maintenance?.enabled == true
    }

    public static func message(config: SYSConfig = .shared) -> String? {
        config.data.maintenance?.message?.resolved()
    }
}

/// Release notes for the running version, shown once after an update.
///
/// Notes live in config rather than in the build, so a typo can be fixed
/// without shipping a release.
public enum SYSWhatsNew {
    private static let seenKey = SYSSettingsKey<String?>("sys.whatsNew.seenVersion", default: nil)

    /// Notes for the current version in the device language, or nil if none.
    public static func notes(config: SYSConfig = .shared) -> [String]? {
        guard let perVersion = config.data.whatsNew?[config.currentVersion] else { return nil }
        for locale in Locale.preferredLanguages {
            if let match = perVersion[String(locale.prefix(2))], !match.isEmpty { return match }
        }
        return perVersion["en"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// True when there are notes for this version that the user hasn't seen.
    public static func shouldShow(config: SYSConfig = .shared) -> Bool {
        guard notes(config: config) != nil else { return false }
        return SYSSettings.shared[seenKey] != config.currentVersion
    }

    public static func markSeen(config: SYSConfig = .shared) {
        SYSSettings.shared[seenKey] = config.currentVersion
    }
}
