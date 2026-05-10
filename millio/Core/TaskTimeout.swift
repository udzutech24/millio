//
//  TaskTimeout.swift
//  millio
//

import Foundation

/// Runs `operation` and cancels it if it doesn't complete within `seconds`.
/// Throws `CancellationError` on timeout; re-throws any error from the operation.
func withTaskTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        guard let result = try await group.next() else {
            group.cancelAll()
            throw CancellationError()
        }
        group.cancelAll()
        return result
    }
}
