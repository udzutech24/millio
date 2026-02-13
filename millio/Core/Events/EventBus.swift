//
//  EventBus.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

/// Базовый протокол для событий приложения
protocol AppEvent {}

/// События backup
enum BackupEvent: AppEvent {
    case started
    case completed(Date)
    case failed(AppError)
    case restoreStarted
    case restoreCompleted
    case restoreFailed(AppError)
}

/// События финансовых сущностей
enum FinanceEvent: AppEvent {
    case cardsUpdated
    case creditsUpdated
    case transactionsUpdated
}

/// Event Bus для слабой связанности между компонентами
@MainActor
final class EventBus {
    static let shared = EventBus()
    
    private var subscribers: [UUID: (AppEvent) -> Void] = [:]
    
    private init() {}
    
    /// Подписаться на события
    func subscribe(_ handler: @escaping (AppEvent) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }
    
    /// Отписаться от событий
    func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
    
    /// Опубликовать событие
    func publish(_ event: AppEvent) {
        for handler in subscribers.values {
            handler(event)
        }
    }
}
