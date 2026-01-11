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

/// Статус подписки
enum SubscriptionStatus {
    case notSubscribed
    case trial
    case subscribed
    case expired
}

/// Протокол для управления подпиской
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
    private let defaults = UserDefaults.standard
    
    // Ключи для хранения статуса локально (offline-first)
    private let subscriptionStatusKey = "subscription_status"
    private let subscriptionExpirationKey = "subscription_expiration"
    private let trialStartDateKey = "trial_start_date"
    private let trialDurationDays = 7
    
    // Product IDs (нужно будет настроить в App Store Connect)
    private let monthlyProductId = "com.millio.pro.monthly"
    private let yearlyProductId = "com.millio.pro.yearly"
    
    @Published private(set) var status: SubscriptionStatus = .notSubscribed
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isTrialActive: Bool = false
    
    private var updateListenerTask: Task<Void, Never>?
    
    private init() {
        // Загружаем локально сохраненный статус (offline-first)
        loadLocalStatus()
        
        // Запускаем слушатель обновлений транзакций
        updateListenerTask = listenForTransactions()
        
        // Проверяем статус при инициализации
        Task {
            await checkSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    func checkSubscriptionStatus() async {
        logger.info("Checking subscription status...")
        
        // Проверяем локальный статус триала
        checkTrialStatus()
        
        // Проверяем активные подписки через StoreKit
        do {
            var hasActiveSubscription = false
            var latestExpirationDate: Date?
            
            // Получаем все активные подписки
            for await result in Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction):
                    if let expirationDate = transaction.expirationDate,
                       expirationDate > Date() {
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
        } catch {
            logger.error("Failed to check subscription status: \(error.localizedDescription)")
            // В случае ошибки используем локально сохраненный статус (offline-first)
            loadLocalStatus()
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
        let trialStartDate = Date()
        defaults.set(trialStartDate, forKey: trialStartDateKey)
        defaults.set(true, forKey: "trial_used")
        
        self.isTrialActive = true
        self.status = .trial
        saveLocalStatus()
        
        logger.info("Trial started, expires: \(trialStartDate.addingTimeInterval(TimeInterval(self.trialDurationDays * 24 * 60 * 60)))")
    }
    
    // MARK: - Private Methods
    
    private func loadLocalStatus() {
        if let statusRaw = defaults.string(forKey: subscriptionStatusKey),
           let status = SubscriptionStatus(rawValue: statusRaw) {
            self.status = status
        }
        
        if let expirationTimestamp = defaults.object(forKey: subscriptionExpirationKey) as? Date {
            self.expirationDate = expirationTimestamp
        }
        
        if let trialStartDate = defaults.object(forKey: trialStartDateKey) as? Date {
            let trialEndDate = trialStartDate.addingTimeInterval(TimeInterval(self.trialDurationDays * 24 * 60 * 60))
            self.isTrialActive = trialEndDate > Date()
        }
    }
    
    private func saveLocalStatus() {
        defaults.set(status.rawValue, forKey: subscriptionStatusKey)
        defaults.set(expirationDate, forKey: subscriptionExpirationKey)
    }
    
    private func checkTrialStatus() {
        guard let trialStartDate = defaults.object(forKey: trialStartDateKey) as? Date else {
            return
        }
        
        let trialEndDate = trialStartDate.addingTimeInterval(TimeInterval(self.trialDurationDays * 24 * 60 * 60))
        
        if trialEndDate > Date() {
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
                do {
                    switch result {
                    case .verified(let transaction):
                        await transaction.finish()
                        await self?.checkSubscriptionStatus()
                    case .unverified:
                        // Пропускаем непроверенные транзакции
                        continue
                    }
                } catch {
                    self?.logger.error("Transaction verification failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
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
    
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Продукт не найден"
        case .userCancelled:
            return "Покупка отменена"
        case .pending:
            return "Покупка ожидает подтверждения"
        case .unknown:
            return "Неизвестная ошибка"
        case .verificationFailed:
            return "Ошибка проверки транзакции"
        case .trialAlreadyUsed:
            return "Пробный период уже использован"
        case .alreadySubscribed:
            return "У вас уже есть активная подписка"
        }
    }
}
