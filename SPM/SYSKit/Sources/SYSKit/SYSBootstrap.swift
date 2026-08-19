import Foundation

/// What the app should show once startup finishes.
public enum SYSAppState: Equatable {
    /// Something is wrong on our side — show the maintenance screen.
    case maintenance(message: String?)
    /// Too old to run. Block, and offer the store link.
    case updateRequired(message: String?, storeURL: URL?)
    /// First run of this onboarding version.
    case onboarding
    /// Just updated, and there are notes for this version.
    case whatsNew([String])
    /// Normal start — show home.
    case ready
}

/// Runs the standard startup sequence.
///
/// Every app does the same things in the same order at launch: load config,
/// record the launch, check the gates, decide what to show. Doing that once here
/// means an app writes screens, not startup plumbing.
///
/// Returns state; it renders nothing. Works the same from a SwiftUI `.task` or a
/// UIKit `Task {}` in a scene delegate, so a UIKit app needs no wrapper.
public enum SYSBootstrap {
    /// How long to wait for fresh config before deciding the gates.
    ///
    /// Config normally applies next launch, so the app stays stable mid-session.
    /// The gates are the exception: a kill switch that needs a relaunch is not a
    /// kill switch. So startup gives the network a brief chance, then proceeds
    /// on cached config regardless — an offline launch is never blocked.
    public static var gateRefreshTimeout: TimeInterval = 2.5

    public static func start(
        config: SYSConfig = .shared,
        onboardingEnabled: Bool = true
    ) async -> SYSAppState {
        // 1. Local config first — instant, always succeeds.
        config.load()

        // 2. Record the launch before anything reads lifecycle state.
        SYSLifecycle.recordLaunch(config: config)

        // 3. Give the network a bounded chance to update the gates.
        await refreshWithTimeout(config: config)

        // 4. Gates first: they override everything else.
        if SYSMaintenance.isActive(config: config) {
            SYSLogger.info("startup: maintenance mode")
            return .maintenance(message: SYSMaintenance.message(config: config))
        }

        if SYSUpdate.status(config: config) == .required {
            SYSLogger.info("startup: update required")
            return .updateRequired(
                message: SYSUpdate.message(config: config),
                storeURL: SYSUpdate.storeURL(config: config)
            )
        }

        // 5. Onboarding before anything else the user could act on.
        if onboardingEnabled, SYSOnboarding.shouldShow {
            return .onboarding
        }

        // 6. Then release notes, once per version.
        if SYSWhatsNew.shouldShow(config: config), let notes = SYSWhatsNew.notes(config: config) {
            return .whatsNew(notes)
        }

        return .ready
    }

    /// Continues after the app dismisses onboarding or what's-new.
    ///
    /// Kept separate so the app decides when its screen is finished rather than
    /// this guessing.
    public static func resume(config: SYSConfig = .shared) -> SYSAppState {
        if SYSOnboarding.shouldShow { return .onboarding }
        if SYSWhatsNew.shouldShow(config: config), let notes = SYSWhatsNew.notes(config: config) {
            return .whatsNew(notes)
        }
        return .ready
    }

    private static func refreshWithTimeout(config: SYSConfig) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await config.refresh() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(gateRefreshTimeout * 1_000_000_000))
            }
            // Whichever finishes first wins; the other is abandoned.
            await group.next()
            group.cancelAll()
        }
    }
}
