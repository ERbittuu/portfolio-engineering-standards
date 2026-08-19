//
//  AnalyticsManager.swift
//  {{PROJECT_NAME}}
//
//  The app's analytics vocabulary. The plumbing — release-only sending, the
//  Firebase wiring, user properties — lives in SYSKit and is shared; only this
//  list of events differs per app.
//
//  This file's path is a fixed contract: scripts/ci/validate_config.py's sibling
//  validate_analytics_events.py greps exactly App/Source/Shared/AnalyticsManager.swift
//  on every PR. Moving or renaming it silently disables that check.
//

import Foundation
import SYSKit

/// Every event this app can send.
///
/// Write cases as `case .x(let y)`, never `case let .x(y)`: the PR check splits
/// on `case .` and skips the `case let` form, so it would report success while
/// checking nothing.
enum AnalyticsEvent: SYSAnalyticsEvent {
    case appOpened
    case screenViewed(screen: String)

    var name: String {
        switch self {
        case .appOpened: return "app_opened"
        case .screenViewed: return "screen_viewed"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .appOpened:
            return [:]
        case .screenViewed(let screen):
            return ["screen": screen]
        }
    }
}

/// Convenience so call sites read `Analytics.track(.appOpened)`.
enum Analytics {
    static func track(_ event: AnalyticsEvent) {
        SYSAnalytics.shared.track(event)
    }
}
