import Foundation
import Testing
@testable import millio

struct RetryPolicyTests {
    @Test("withRetry does not retry when shouldRetry returns false")
    func testWithRetryDoesNotRetry() async {
        let policy = RetryPolicy(maxAttempts: 3, delay: 0, backoffMultiplier: 1)
        var attempts = 0
        
        do {
            _ = try await withRetry(policy: policy, shouldRetry: { _ in false }) {
                attempts += 1
                throw AppError.iCloudUnavailable
            }
            #expect(false)
        } catch let error as AppError {
            #expect(error == .iCloudUnavailable)
            #expect(attempts == 1)
        } catch {
            #expect(false)
        }
    }
    
    @Test("withRetry retries until success when shouldRetry returns true")
    func testWithRetryRetriesUntilSuccess() async throws {
        let policy = RetryPolicy(maxAttempts: 3, delay: 0, backoffMultiplier: 1)
        var attempts = 0
        
        let value: Int = try await withRetry(policy: policy, shouldRetry: { _ in true }) {
            attempts += 1
            if attempts < 3 {
                throw AppError.backupFailed("transient")
            }
            return 42
        }
        
        #expect(value == 42)
        #expect(attempts == 3)
    }
}

