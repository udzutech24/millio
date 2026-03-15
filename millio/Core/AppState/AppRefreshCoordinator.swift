//
//  AppRefreshCoordinator.swift
//  millio
//
//  Created by Codex on 15.03.2026.
//

import Foundation
import OSLog

@MainActor
protocol SubscriptionRefreshing: AnyObject {
    var snapshot: SubscriptionSnapshot { get }
    func checkSubscriptionStatus(force: Bool) async
}

@MainActor
protocol AuthUserRefreshing: AnyObject {
    var isAuthenticated: Bool { get }
    func reloadCurrentUser() async
}

extension SubscriptionManager: SubscriptionRefreshing {}
extension AuthManager: AuthUserRefreshing {}

enum AppRefreshReason: String {
    case coldStart
    case appDidBecomeActive
    case profileAppeared
}

@MainActor
final class AppRefreshCoordinator {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "AppRefreshCoordinator")
    private let now: () -> Date
    private let subscriptionCooldown: TimeInterval
    private let authCooldown: TimeInterval

    private var subscriptionTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var lastSubscriptionRefreshAt: Date?
    private var lastAuthRefreshAt: Date?
    private var isColdStartRefreshInProgress = false
    private var hasCompletedInitialStartupRefresh = false
    private var shouldSkipNextForegroundSubscriptionRefresh = false

    init(
        now: @escaping () -> Date = Date.init,
        subscriptionCooldown: TimeInterval = 5,
        authCooldown: TimeInterval = 30
    ) {
        self.now = now
        self.subscriptionCooldown = max(0, subscriptionCooldown)
        self.authCooldown = max(0, authCooldown)
    }

    func refreshSubscriptionIfNeeded(
        reason: AppRefreshReason,
        appState: AppState,
        subscriptionManager: any SubscriptionRefreshing,
        force: Bool = false
    ) async {
        if reason == .appDidBecomeActive, !hasCompletedInitialStartupRefresh, !force {
            logger.info("Skipping subscription refresh reason=\(reason.rawValue, privacy: .public) until initial startup refresh completes")
            appState.applySubscriptionSnapshot(subscriptionManager.snapshot)
            return
        }

        if reason == .appDidBecomeActive, shouldSkipNextForegroundSubscriptionRefresh, !force {
            shouldSkipNextForegroundSubscriptionRefresh = false
            logger.info("Skipping subscription refresh reason=\(reason.rawValue, privacy: .public) because startup already covered the initial foreground pass")
            appState.applySubscriptionSnapshot(subscriptionManager.snapshot)
            return
        }

        if reason == .appDidBecomeActive, isColdStartRefreshInProgress, !force {
            logger.info("Skipping subscription refresh reason=\(reason.rawValue, privacy: .public) while cold start refresh is in progress")
            appState.applySubscriptionSnapshot(subscriptionManager.snapshot)
            return
        }

        if !force, let subscriptionTask {
            await subscriptionTask.value
            return
        }

        if !force,
           let lastSubscriptionRefreshAt,
           now().timeIntervalSince(lastSubscriptionRefreshAt) < subscriptionCooldown {
            logger.info("Skipping subscription refresh reason=\(reason.rawValue, privacy: .public) due to cooldown")
            appState.applySubscriptionSnapshot(subscriptionManager.snapshot)
            return
        }

        let task = Task { @MainActor [weak self] in
            if reason == .coldStart {
                self?.isColdStartRefreshInProgress = true
            }
            self?.logger.info("Starting subscription refresh reason=\(reason.rawValue, privacy: .public) force=\(force, privacy: .public)")
            await subscriptionManager.checkSubscriptionStatus(force: force)
            appState.applySubscriptionSnapshot(subscriptionManager.snapshot)
            self?.lastSubscriptionRefreshAt = self?.now()
            if reason == .coldStart {
                self?.isColdStartRefreshInProgress = false
                self?.hasCompletedInitialStartupRefresh = true
                self?.shouldSkipNextForegroundSubscriptionRefresh = true
            }
            self?.subscriptionTask = nil
        }

        subscriptionTask = task
        await task.value
    }

    func refreshSubscriptionIfNeeded(
        reason: AppRefreshReason,
        appState: AppState,
        force: Bool = false
    ) async {
        await refreshSubscriptionIfNeeded(
            reason: reason,
            appState: appState,
            subscriptionManager: SubscriptionManager.shared,
            force: force
        )
    }

    func refreshAuthenticatedUserIfNeeded(
        reason: AppRefreshReason,
        authManager: any AuthUserRefreshing,
        force: Bool = false
    ) async {
        guard authManager.isAuthenticated else { return }

        if !force, let authTask {
            await authTask.value
            return
        }

        if !force,
           let lastAuthRefreshAt,
           now().timeIntervalSince(lastAuthRefreshAt) < authCooldown {
            logger.info("Skipping auth user refresh reason=\(reason.rawValue, privacy: .public) due to cooldown")
            return
        }

        let task = Task { @MainActor [weak self] in
            self?.logger.info("Starting auth user refresh reason=\(reason.rawValue, privacy: .public) force=\(force, privacy: .public)")
            await authManager.reloadCurrentUser()
            self?.lastAuthRefreshAt = self?.now()
            self?.authTask = nil
        }

        authTask = task
        await task.value
    }
}
