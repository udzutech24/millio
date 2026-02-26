//
//  ServiceItemTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct ServiceItemTests {
    @Test("Список сервисов содержит только актуальные разделы")
    func testAllServicesContainsOnlyActiveItems() {
        let services = ServiceItem.allServices()
        let ids = services.map { $0.id }

        #expect(ids.contains("finances"))
        #expect(ids.contains("courses"))
        #expect(ids.contains("cashback"))
        #expect(ids.contains("cashflow"))

        #expect(!ids.contains("credits"))
        #expect(!ids.contains("cards"))
        #expect(!ids.contains("investments"))

        let cashback = services.first { $0.id == "cashback" }
        #expect(cashback?.icon == ServiceItem.cashbackIconAssetName)
    }

    @Test("Порядок сервисов игнорирует удаленные разделы")
    func testOrderManagerSkipsRemovedServices() {
        let defaults = UserDefaults.standard
        let storageKey = "service_order"
        defaults.set(["credits", "finances", "cards", "cashback"], forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let manager = ServiceOrderManager()
        let ids = manager.getOrderedServices().map { $0.id }

        #expect(ids.prefix(2) == ["finances", "cashback"])
        #expect(Set(ids) == Set(["finances", "courses", "cashback", "cashflow"]))
        #expect(!ids.contains("credits"))
        #expect(!ids.contains("cards"))
        #expect(!ids.contains("investments"))
    }
}
