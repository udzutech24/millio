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

    @Test("Сервисы на главном экране используют ключи локализации main.service.*")
    func testMainServicesUseLocalizationKeys() {
        let services = ServiceItem.allServices()
        let keys = services.map(\.titleKey)

        #expect(keys.count == Set(keys).count)
        #expect(keys.allSatisfy { $0.hasPrefix("main.service.") })
    }

    @Test("Порядок сервисов игнорирует удаленные разделы")
    func testOrderManagerSkipsRemovedServices() {
        let defaults = UserDefaults.standard
        let storageKey = "service_order"
        defaults.set(["credits", "finances", "cards", "cashback"], forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let manager = ServiceOrderManager()
        let ids = manager.getOrderedServices().map { $0.id }
        let allServiceIDs = Set(ServiceItem.allServices().map { $0.id })

        #expect(ids.prefix(2) == ["finances", "cashback"])
        #expect(Set(ids) == allServiceIDs)
        #expect(!ids.contains("credits"))
        #expect(!ids.contains("cards"))
        #expect(!ids.contains("investments"))
    }

    @Test("Порядок сервисов сохраняется и восстанавливается после перестановки")
    func testOrderManagerPersistsCustomOrder() {
        let defaults = UserDefaults.standard
        let storageKey = "service_order"
        defaults.removeObject(forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let manager = ServiceOrderManager()
        let existingIDs = ServiceItem.allServices().map { $0.id }
        let customOrder = Array(existingIDs.prefix(4).reversed())

        manager.saveOrder(customOrder)
        let loadedOrder = manager.loadOrder()
        let orderedServices = manager.getOrderedServices().map { $0.id }

        #expect(loadedOrder == customOrder)
        // Первые 4 — в сохранённом порядке; новые сервисы добавляются в конец
        #expect(orderedServices.prefix(4) == ArraySlice(customOrder))
        #expect(Set(orderedServices) == Set(existingIDs))
    }
}
