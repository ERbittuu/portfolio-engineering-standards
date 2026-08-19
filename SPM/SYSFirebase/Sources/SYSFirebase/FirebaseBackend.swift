import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation
import SYSKit

/// Connects SYSKit's protocols to Firebase.
///
/// The only file in the system that imports Firebase, which is what keeps SYSKit
/// itself dependency-free and testable without it.
public final class SYSFirebaseBackend: SYSAnalyticsBackend, SYSErrorReporter {
    public init() {}

    /// Wires Firebase into SYSKit. Call once at launch, before SYSBootstrap.
    public static func install() {
        let backend = SYSFirebaseBackend()
        SYSAnalytics.shared.configure(backend: backend)
        SYSLogger.reporter = backend
    }

    // MARK: SYSAnalyticsBackend

    public func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    public func log(name: String, parameters: [String: Any]) {
        Analytics.logEvent(name, parameters: parameters)
    }

    public func setUserID(_ id: String?) {
        Analytics.setUserID(id)
        Crashlytics.crashlytics().setUserID(id)
    }

    public func setUserProperty(_ value: String?, for name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    // MARK: SYSErrorReporter

    /// Non-fatals, so failures that never crash the app are still visible.
    public func report(message: String, error: Error?) {
        if let error {
            Crashlytics.crashlytics().record(error: error, userInfo: ["message": message])
        } else {
            Crashlytics.crashlytics().record(
                error: NSError(domain: "SYSKit", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            )
        }
    }

    public func breadcrumb(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }
}
