//
//  ServiceItem.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftUI

/// Элемент сервиса для главного экрана
struct ServiceItem: Identifiable, Equatable {
    let id: String
    let route: AppRoute
    let title: String
    let icon: String
    let gradientColors: [Color]
    
    static func allServices() -> [ServiceItem] {
        [
            ServiceItem(
                id: "finances",
                route: .finances,
                title: "Финансы",
                icon: "finance",
                gradientColors: AppColors.financesGradient
            ),
            ServiceItem(
                id: "courses",
                route: .courses,
                title: "Курсы",
                icon: "courses",
                gradientColors: AppColors.coursesGradient
            ),
            ServiceItem(
                id: "cashback",
                route: .cashback,
                title: "Кешбэк",
                icon: "cashback",
                gradientColors: AppColors.cashbackGradient
            ),
            ServiceItem(
                id: "cashflow",
                route: .cashflow,
                title: "Кэшфлоу",
                icon: "loans",
                gradientColors: AppColors.cashflowGradient
            )
        ]
    }
}

/// Менеджер для управления порядком сервисов
final class ServiceOrderManager {
    private static let key = "service_order"
    private let defaults = UserDefaults.standard
    
    /// Загрузить сохраненный порядок сервисов
    func loadOrder() -> [String] {
        if let order = defaults.array(forKey: Self.key) as? [String] {
            return order
        }
        // Возвращаем порядок по умолчанию
        return ServiceItem.allServices().map { $0.id }
    }
    
    /// Сохранить порядок сервисов
    func saveOrder(_ order: [String]) {
        defaults.set(order, forKey: Self.key)
    }
    
    /// Получить упорядоченный список сервисов
    func getOrderedServices() -> [ServiceItem] {
        let order = loadOrder()
        let allServices = ServiceItem.allServices()
        let serviceDict = Dictionary(uniqueKeysWithValues: allServices.map { ($0.id, $0) })
        
        // Сначала добавляем сервисы в сохраненном порядке
        var ordered: [ServiceItem] = []
        for id in order {
            if let service = serviceDict[id] {
                ordered.append(service)
            }
        }
        
        // Затем добавляем новые сервисы, которых нет в сохраненном порядке
        for service in allServices {
            if !order.contains(service.id) {
                ordered.append(service)
            }
        }
        
        return ordered
    }
}
