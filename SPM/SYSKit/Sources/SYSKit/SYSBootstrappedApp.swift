#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI

/// An `App` whose launch sequence is wired for it.
///
/// Conforming supplies the screens; this supplies the order they appear in, the
/// `.task` that starts everything, and the retry path. The wiring is the part
/// that was identical in every app and the part that fails quietly: forget the
/// `.task` and the app sits on its loading screen forever, with nothing in the
/// log to say why.
///
/// ```swift
/// @main
/// struct ColorfulApp: App, SYSBootstrappedApp {
///     @StateObject var startup = SYSStartup(requiresAssets: true)
///
///     @ViewBuilder
///     func screen(for state: SYSAppState?) -> some View {
///         switch state {
///         case .none:  LoadingView(progress: startup.progress?.fraction)
///         case .ready: HomeView()
///         ...
///         }
///     }
/// }
/// ```
///
/// This renders nothing of its own — no loading screen, no error screen, no
/// styling. Every pixel is still the app's, which is why a shared module can
/// carry it without deciding how anyone's product looks.
///
/// An app that needs a scene this shape cannot express — several windows,
/// commands, a document group — implements `body` itself and calls
/// `startup.begin` from its own `.task`. The protocol is a convenience, not a
/// cage.
@MainActor
public protocol SYSBootstrappedApp: App {
    associatedtype Screen: View

    /// Declare as `@StateObject` so it survives redraws.
    var startup: SYSStartup { get }

    /// What to show for each startup state, including `nil` while it runs.
    @ViewBuilder func screen(for state: SYSAppState?) -> Screen

    /// Runs after a successful launch and *before* the state is published, so
    /// anything prepared here is in place before the first screen appears.
    func afterReady() async

    /// Wraps the root — colour scheme, environment objects, a backdrop that sits
    /// behind every state. Defaults to no change.
    @ViewBuilder func decorate(_ content: Screen) -> AnyView

}

/// What a blocking state offers the user, if anything.
///
/// The wording and the icon are the app's — a shared module writing sentences
/// for someone else's product would be wrong, and copy is the part that should
/// differ. What should *not* differ is whether a button appears at all: a retry
/// on a 404 or a hash mismatch re-fetches the same failure, and an update prompt
/// with no store link is a dead end. That decision lives here so apps cannot
/// quietly disagree about it.
public enum SYSStateAction {
    /// Nothing useful to offer; show the message alone.
    case none
    /// Worth another attempt.
    case retry(() -> Void)
    /// Needs a newer build; the URL is the store page.
    case update(URL)
}

@MainActor
public extension SYSBootstrappedApp {
    func afterReady() async {}

    func decorate(_ content: Screen) -> AnyView { AnyView(content) }

    var body: some Scene {
        WindowGroup {
            decorate(screen(for: startup.state))
                // Deliberately not `.task`. Its opaque return type lives in
                // SwiftUICore, which a Swift package is not an allowed client of,
                // so a device archive fails to link with an undefined symbol
                // while the simulator build passes. onAppear plus an explicit
                // Task produces the same behaviour and links everywhere.
                //
                // SwiftUI may run this more than once for the same view; begin()
                // ignores the repeat rather than launching twice.
                .onAppear {
                    Task { await startup.begin(afterReady: afterReady) }
                }
        }
    }

    /// Re-attempts a failed content download. Wire to the retry button.
    func retryStartup() {
        startup.retry(afterReady: afterReady)
    }

    // MARK: What a blocking state offers
    //
    // Icons and sentences stay with the app. Only the decision is shared.

    /// Whether a blocking state has an action worth showing, and which.
    func action(for state: SYSAppState) -> SYSStateAction {
        switch state {
        case let .updateRequired(_, storeURL):
            return storeURL.map { .update($0) } ?? .none
        case let .dataUnavailable(error):
            return error.isRetryable ? .retry { retryStartup() } : .none
        default:
            return .none
        }
    }
}

#endif
