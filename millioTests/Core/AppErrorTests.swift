//
//  AppErrorTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Testing
@testable import millio

struct AppErrorTests {
    @Test("Error equality works correctly")
    func testErrorEquality() {
        #expect(AppError.iCloudUnavailable == AppError.iCloudUnavailable)
        #expect(AppError.networkUnavailable == AppError.networkUnavailable)
        #expect(AppError.backupCorrupted == AppError.backupCorrupted)
        
        let error1 = AppError.restoreFailed("test")
        let error2 = AppError.restoreFailed("test")
        #expect(error1 == error2)

        let securityError1 = AppError.securityFailed("pin")
        let securityError2 = AppError.securityFailed("pin")
        #expect(securityError1 == securityError2)
    }
    
    @Test("Different errors are not equal")
    func testErrorInequality() {
        #expect(AppError.iCloudUnavailable != AppError.networkUnavailable)
        
        let error1 = AppError.restoreFailed("test1")
        let error2 = AppError.restoreFailed("test2")
        #expect(error1 != error2)

        let securityError1 = AppError.securityFailed("pin1")
        let securityError2 = AppError.securityFailed("pin2")
        #expect(securityError1 != securityError2)
    }
    
    @Test("Error has localized description")
    func testLocalizedDescription() {
        let error = AppError.iCloudUnavailable
        #expect(!error.localizedDescription.isEmpty)
        #expect(error.localizedDescription.contains("iCloud"))

        let securityError = AppError.securityFailed("PIN")
        #expect(securityError.localizedDescription.contains("Ошибка безопасности"))
    }
}
