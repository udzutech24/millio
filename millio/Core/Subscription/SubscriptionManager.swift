//
//  SubscriptionManager.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import StoreKit
import OSLog
import Combine

enum SubscriptionAccessSource: String, CaseIterable {
    case free
    case trial
    case subscription
    case debug

    var hasPremiumAccess: Bool {
        switch self {
        case .free:
            return false
        case .trial, .subscription, .debug:
            return true
        }
    }
}

struct SubscriptionSnapshot {
    let status: SubscriptionStatus
    let expirationDate: Date?
    let isTrialActive: Bool
    let hasDebugPremiumOverride: Bool
    let hasTrialDisabledOverride: Bool

    var accessSource: SubscriptionAccessSource {
        if hasDebugPremiumOverride {
            return .debug
        }
        if hasTrialDisabledOverride, status == .trial {
            return .free
        }
        switch status {
        case .trial:
            return .trial
        case .subscribed:
            return .subscription
        case .notSubscribed, .expired:
            return .free
        }
    }

    var isPro: Bool {
        accessSource.hasPremiumAccess
    }
}

/// Статус подписки
enum SubscriptionStatus {
    case notSubscribed
    case trial
    case subscribed
    case expired
}

/// Протокол для управления подпиской
@MainActor
protocol SubscriptionManagerProtocol {
    var status: SubscriptionStatus { get }
    var expirationDate: Date? { get }
    var isTrialActive: Bool { get }
    
    func checkSubscriptionStatus() async
    func purchaseSubscription(productId: String) async throws
    func restorePurchases() async throws
    func startTrial() async throws
}

/// Менеджер подписки с использованием StoreKit 2
@MainActor
final class SubscriptionManager: SubscriptionManagerProtocol {
    static let shared = SubscriptionManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "SubscriptionManager")
    private let defaults: UserDefaults
    private let now: () -> Date
    
    // Ключи для хранения статуса локально (offline-first)
    private let subscriptionStatusKey = "subscription_status"
    private let subscriptionExpirationKey = "subscription_expiration"
    private let trialStartDateKey = "trial_start_date"
    private let debugPremiumKey = "debug_premium_enabled"
    private let debugSubscriptionExpirationKey = "debug_subscription_expiration"
    private let trialDisabledOverrideKey = "debug_trial_disabled_override"
    private let trialDurationDays = 7
    
    // Product IDs (нужно будет настроить в App Store Connect)
    private let monthlyProductId = "com.millio.pro.monthly"
    private let yearlyProductId = "com.millio.pro.yearly"
    
    @Published private(set) var status: SubscriptionStatus = .notSubscribed
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isTrialActive: Bool = false
    
    private var updateListenerTask: Task<Void, Never>?
    
    init(
        defaults: UserDefaults = .standard,
        startTransactionListener: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
        
        // Загружаем локально сохраненный статус (offline-first)
        loadLocalStatus()
        
        // Запускаем слушатель обновлений транзакций
        if startTransactionListener {
            updateListenerTask = listenForTransactions()
        } else {
            updateListenerTask = nil
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    func checkSubscriptionStatus() async {
        logger.info("Checking subscription status...")
        
        // Если включен дебаг-премиум, не проверяем StoreKit
        if defaults.bool(forKey: debugPremiumKey),
           let expiration = defaults.object(forKey: debugSubscriptionExpirationKey) as? Date,
           expiration > now() {
            self.status = .subscribed
            self.expirationDate = expiration
            self.isTrialActive = false
            syncWidgetSubscriptionSnapshot()
            logger.info("Debug premium is active, expires: \(expiration)")
            return
        }
        
        // Проверяем локальный статус триала
        checkTrialStatus()
        
        // Проверяем активные подписки через StoreKit
        var hasActiveSubscription = false
        var latestExpirationDate: Date?
        
        // Получаем все активные подписки
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if let expirationDate = transaction.expirationDate,
                   expirationDate > now() {
                    hasActiveSubscription = true
                    if latestExpirationDate == nil || expirationDate > latestExpirationDate! {
                        latestExpirationDate = expirationDate
                    }
                }
            case .unverified:
                continue
            }
        }
        
        if hasActiveSubscription, let expiration = latestExpirationDate {
            self.status = .subscribed
            self.expirationDate = expiration
            self.isTrialActive = false
            saveLocalStatus()
            logger.info("Active subscription found, expires: \(expiration)")
        } else {
            // Если нет активной подписки, проверяем триал
            if isTrialActive {
                self.status = .trial
            } else {
                self.status = .notSubscribed
            }
            self.expirationDate = nil
            saveLocalStatus()
            logger.info("No active subscription found")
        }
    }
    
    func purchaseSubscription(productId: String) async throws {
        logger.info("Purchasing subscription: \(productId)")
        
        guard let product = try? await Product.products(for: [productId]).first else {
            throw SubscriptionError.productNotFound
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            
            // Обновляем статус после успешной покупки
            await checkSubscriptionStatus()
            
            logger.info("Subscription purchased successfully")
            
        case .userCancelled:
            throw SubscriptionError.userCancelled
            
        case .pending:
            throw SubscriptionError.pending
            
        @unknown default:
            throw SubscriptionError.unknown
        }
    }
    
    func restorePurchases() async throws {
        logger.info("Restoring purchases...")
        
        try await AppStore.sync()
        await checkSubscriptionStatus()
        
        logger.info("Purchases restored")
    }
    
    func startTrial() async throws {
        logger.info("Starting trial...")
        
        // Проверяем, не использовался ли уже триал
        if defaults.bool(forKey: "trial_used") {
            throw SubscriptionError.trialAlreadyUsed
        }
        
        // Проверяем, нет ли уже активной подписки
        if status == .subscribed || status == .trial {
            throw SubscriptionError.alreadySubscribed
        }
        
        // Устанавливаем дату начала триала
        let trialStartDate = now()
        defaults.set(trialStartDate, forKey: trialStartDateKey)
        defaults.set(true, forKey: "trial_used")

        // Если пользователь/дебаг отключил триал, не даем premium через trial даже при валидной дате.
        checkTrialStatus()
        if isTrialActive {
            self.status = .trial
        } else if status == .trial {
            self.status = .notSubscribed
        }
        saveLocalStatus()
        
        logger.info("Trial started, expires: \(trialStartDate.addingTimeInterval(TimeInterval(self.trialDurationDays * 24 * 60 * 60)))")
    }
    
    func grantDebugPremium() {
        logger.info("Granting debug premium access...")
        
        // Устанавливаем премиум доступ на год вперед
        let expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: now()) ?? now()
        defaults.set(true, forKey: debugPremiumKey)
        defaults.set(expirationDate, forKey: debugSubscriptionExpirationKey)
        self.status = .subscribed
        self.expirationDate = expirationDate
        self.isTrialActive = false
        syncWidgetSubscriptionSnapshot()
        // Не вызываем saveLocalStatus(), чтобы не перезаписать реальную дату подписки
        
        logger.info("Debug premium granted, expires: \(expirationDate)")
    }
    
    func revokeDebugPremium() {
        logger.info("Revoking debug premium access...")
        
        // Очищаем только debug ключи, не трогая реальную подписку
        defaults.set(false, forKey: debugPremiumKey)
        defaults.removeObject(forKey: debugSubscriptionExpirationKey)
        self.status = .notSubscribed
        self.expirationDate = nil  // Очищаем память от debug значения
        self.isTrialActive = false
        syncWidgetSubscriptionSnapshot()
        // Не вызываем saveLocalStatus(), чтобы не затереть реальную дату истечения подписки StoreKit
        // Если есть реальная подписка, вызывающий код должен вызвать checkSubscriptionStatus()
        
        logger.info("Debug premium revoked")
    }
    
    var hasDebugPremiumOverride: Bool {
        guard defaults.bool(forKey: debugPremiumKey),
              let expirationDate = defaults.object(forKey: debugSubscriptionExpirationKey) as? Date else {
            return false
        }
        return expirationDate > now()
    }

    var isDebugPremiumActive: Bool {
        hasDebugPremiumOverride
    }

    var hasTrialDisabledOverride: Bool {
        defaults.bool(forKey: trialDisabledOverrideKey)
    }

    func setTrialDisabledOverride(_ enabled: Bool) {
        defaults.set(enabled, forKey: trialDisabledOverrideKey)
        // Локально пересчитываем trial. StoreKit подписка проверяется отдельным вызовом checkSubscriptionStatus().
        checkTrialStatus()
        saveLocalStatus()
    }

    var snapshot: SubscriptionSnapshot {
        SubscriptionSnapshot(
            status: status,
            expirationDate: expirationDate,
            isTrialActive: isTrialActive,
            hasDebugPremiumOverride: hasDebugPremiumOverride,
            hasTrialDisabledOverride: hasTrialDisabledOverride
        )
    }
    
    // MARK: - Private Methods
    
    private func loadLocalStatus() {
        // Если включен дебаг-премиум, загружаем его статус из debug ключа
        if defaults.bool(forKey: debugPremiumKey),
           let expiration = defaults.object(forKey: debugSubscriptionExpirationKey) as? Date,
           expiration > now() {
            self.status = .subscribed
            self.expirationDate = expiration
            self.isTrialActive = false
            return
        }
        
        if let statusRaw = defaults.string(forKey: subscriptionStatusKey),
           let status = SubscriptionStatus(rawValue: statusRaw) {
            self.status = status
        }
        
        if let expirationTimestamp = defaults.object(forKey: subscriptionExpirationKey) as? Date {
            self.expirationDate = expirationTimestamp
        }

        checkTrialStatus()
        
        syncWidgetSubscriptionSnapshot()
    }
    
    private func saveLocalStatus() {
        defaults.set(status.rawValue, forKey: subscriptionStatusKey)
        // Не сохраняем expirationDate в subscriptionExpirationKey если включен debug premium,
        // чтобы не перезаписать реальную дату истечения подписки StoreKit
        if !defaults.bool(forKey: debugPremiumKey) {
            defaults.set(expirationDate, forKey: subscriptionExpirationKey)
        }
        
        syncWidgetSubscriptionSnapshot()
    }
    
    private func checkTrialStatus() {
        // Debug override: форсируем отсутствие триала, не трогая флаг "trial_used".
        if defaults.bool(forKey: trialDisabledOverrideKey) {
            self.isTrialActive = false
            if status == .trial {
                self.status = .notSubscribed
            }
            return
        }

        guard let trialStartDate = defaults.object(forKey: trialStartDateKey) as? Date else {
            return
        }
        
        let trialEndDate = trialStartDate.addingTimeInterval(TimeInterval(self.trialDurationDays * 24 * 60 * 60))
        
        if trialEndDate > now() {
            self.isTrialActive = true
            if status != .subscribed {
                self.status = .trial
            }
        } else {
            self.isTrialActive = false
            if status == .trial {
                self.status = .expired
            }
        }
    }
    
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self?.checkSubscriptionStatus()
                case .unverified:
                    // Пропускаем непроверенные транзакции
                    continue
                }
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    private func syncWidgetSubscriptionSnapshot() {
        CurrencyWidgetSyncService.syncSubscription(
            statusRaw: status.rawValue,
            expirationDate: expirationDate,
            isTrialActive: isTrialActive,
            debugPremiumEnabled: defaults.bool(forKey: debugPremiumKey),
            debugPremiumExpiration: defaults.object(forKey: debugSubscriptionExpirationKey) as? Date
        )
    }
    
    // MARK: - Product IDs
    
    var monthlyProductID: String {
        monthlyProductId
    }
    
    var yearlyProductID: String {
        yearlyProductId
    }
}

// MARK: - SubscriptionStatus Extension

extension SubscriptionStatus {
    var rawValue: String {
        switch self {
        case .notSubscribed: return "notSubscribed"
        case .trial: return "trial"
        case .subscribed: return "subscribed"
        case .expired: return "expired"
        }
    }
    
    init?(rawValue: String) {
        switch rawValue {
        case "notSubscribed": self = .notSubscribed
        case "trial": self = .trial
        case "subscribed": self = .subscribed
        case "expired": self = .expired
        default: return nil
        }
    }
}

// MARK: - Subscription Errors

enum SubscriptionError: LocalizedError {
    case productNotFound
    case userCancelled
    case pending
    case unknown
    case verificationFailed
    case trialAlreadyUsed
    case alreadySubscribed

    private var localizationKey: String {
        switch self {
        case .productNotFound:
            return "subscription.error.product_not_found"
        case .userCancelled:
            return "subscription.error.user_cancelled"
        case .pending:
            return "subscription.error.pending"
        case .unknown:
            return "subscription.error.unknown"
        case .verificationFailed:
            return "subscription.error.verification_failed"
        case .trialAlreadyUsed:
            return "subscription.error.trial_already_used"
        case .alreadySubscribed:
            return "subscription.error.already_subscribed"
        }
    }

    func localizedDescription(for locale: Locale) -> String {
        AppLocalization.string(localizationKey, locale: locale)
    }
    
    var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}
