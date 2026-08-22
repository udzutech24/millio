import Foundation

/// Chooses only the optional splash override. The normal launch policy remains owned by
/// `AppLifecycleUseCase`; a cached authenticated session is the sole case that may skip it.
enum ColdStartPresentationPolicy {
    static func minimumLaunchDurationOverride(
        hasCachedAuthenticatedSession: Bool
    ) -> TimeInterval? {
        hasCachedAuthenticatedSession ? 0 : nil
    }
}
