//
//  RetryPolicy.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

/// Политика повторов для сетевых операций
nonisolated struct RetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval
    let backoffMultiplier: Double
    
    nonisolated static let `default` = RetryPolicy(maxAttempts: 3, delay: 1.0, backoffMultiplier: 2.0)
    nonisolated static let aggressive = RetryPolicy(maxAttempts: 5, delay: 0.5, backoffMultiplier: 1.5)
    nonisolated static let conservative = RetryPolicy(maxAttempts: 2, delay: 2.0, backoffMultiplier: 3.0)
}

/// Выполняет операцию с повторами согласно политике
func withRetry<T>(
    policy: RetryPolicy = .default,
    operation: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    var currentDelay = policy.delay
    
    for attempt in 1...policy.maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            
            if attempt < policy.maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                currentDelay *= policy.backoffMultiplier
            }
        }
    }
    
    throw lastError ?? NSError(domain: "Retry", code: -1, userInfo: [NSLocalizedDescriptionKey: "Retry failed after \(policy.maxAttempts) attempts"])
}
