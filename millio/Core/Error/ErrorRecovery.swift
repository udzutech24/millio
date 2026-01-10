//
//  ErrorRecovery.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

/// Стратегия восстановления от ошибок
protocol ErrorRecoveryStrategy {
    func canRecover(from error: AppError) -> Bool
    func recover(from error: AppError) async throws
}

/// Действие после попытки восстановления
enum ErrorRecoveryAction {
    case retry
    case fallback
    case ignore
    case showError
}

/// Менеджер восстановления от ошибок
@MainActor
final class ErrorRecoveryManager {
    private let strategies: [ErrorRecoveryStrategy]
    
    init(strategies: [ErrorRecoveryStrategy] = []) {
        self.strategies = strategies.isEmpty ? [NetworkErrorRecoveryStrategy()] : strategies
    }
    
    func handle(_ error: AppError) async -> ErrorRecoveryAction {
        for strategy in strategies {
            if strategy.canRecover(from: error) {
                do {
                    try await strategy.recover(from: error)
                    return .retry
                } catch {
                    continue
                }
            }
        }
        return .showError
    }
}

// MARK: - Network Error Recovery

struct NetworkErrorRecoveryStrategy: ErrorRecoveryStrategy {
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    
    func canRecover(from error: AppError) -> Bool {
        error == .networkUnavailable || error == .iCloudUnavailable
    }
    
    func recover(from error: AppError) async throws {
        for attempt in 1...maxRetries {
            try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
            
            // Проверка доступности сети/iCloud
            // В реальной реализации здесь была бы проверка доступности
            if await checkNetworkAvailability() {
                return
            }
        }
        throw error
    }
    
    private func checkNetworkAvailability() async -> Bool {
        // Упрощенная проверка - в реальности нужна более сложная логика
        // Например, через Network framework или CloudKit availability check
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 секунды
        return true // Заглушка
    }
}
