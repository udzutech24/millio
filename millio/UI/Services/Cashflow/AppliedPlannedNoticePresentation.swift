//
//  AppliedPlannedNoticePresentation.swift
//  millio
//
//  Решение «показывать сводку / подождать / показывать нечего» — чистая функция.
//  Фаза 2 плана plans/2026-09-05__planned-operations-applied-notice.md.
//
//  Почему решение вынесено из вью: показ гардится теми же условиями, что и лист входящей
//  выписки (блокировка, готовность стора, смена scope, restore), а проверить их в SwiftUI-теле
//  нечем. Здесь — тестируемая таблица условий, вью только исполняет вердикт.
//

import Foundation

// MARK: - AppliedPlannedNoticeItem

/// Сводка, готовая к показу. Обёртка нужна только чтобы отдать digest в `sheet(item:)`:
/// `AppliedPlannedDigest` — значение без идентичности, а лист требует `Identifiable`.
struct AppliedPlannedNoticeItem: Identifiable, Equatable {
    let id: UUID
    let digest: AppliedPlannedDigest

    init(id: UUID = UUID(), digest: AppliedPlannedDigest) {
        self.id = id
        self.digest = digest
    }
}

// MARK: - AppliedPlannedNoticePresentation

enum AppliedPlannedNoticePresentation {

    /// Состояние приложения на момент попытки показа. Ровно те же условия, по которым
    /// гардится лист входящей выписки (`millioApp.presentNextIncomingStatementIfReady`).
    struct Readiness: Equatable {
        /// Экран блокировки / системный промпт Face ID поверх интерфейса.
        let isAppLocked: Bool
        /// `lifecycle == .ready` и контейнер данных открыт.
        let isStoreReady: Bool
        /// Идёт restore, смена scope или сверка — поверх интерфейса свой оверлей.
        let isModalBusy: Bool
        /// Лист входящей выписки уже занял очередь: он приоритетнее сводки.
        let hasPendingStatement: Bool
        /// Сводка уже показывается (digest забран) — второй раз показывать нечего.
        let isAlreadyPresenting: Bool

        init(
            isAppLocked: Bool,
            isStoreReady: Bool,
            isModalBusy: Bool,
            hasPendingStatement: Bool,
            isAlreadyPresenting: Bool
        ) {
            self.isAppLocked = isAppLocked
            self.isStoreReady = isStoreReady
            self.isModalBusy = isModalBusy
            self.hasPendingStatement = hasPendingStatement
            self.isAlreadyPresenting = isAlreadyPresenting
        }
    }

    enum Decision: Equatable {
        /// Забрать digest и показать лист.
        case show
        /// Показать есть что, но не сейчас — журнал не трогать, дождаться следующего триггера
        /// (снятие блокировки, `lifecycle == .ready`, закрытие листа выписки).
        case wait
        /// Показывать нечего.
        case nothing
    }

    /// `hasPendingNotice` спрашивается у журнала БЕЗ его очистки: `.wait` обязан оставить
    /// сводку в журнале, иначе применённые операции пропадут молча.
    static func decide(hasPendingNotice: Bool, readiness: Readiness) -> Decision {
        guard !readiness.isAlreadyPresenting else { return .nothing }
        guard hasPendingNotice else { return .nothing }
        if readiness.isAppLocked
            || !readiness.isStoreReady
            || readiness.isModalBusy
            || readiness.hasPendingStatement {
            return .wait
        }
        return .show
    }

    /// Единственный способ превратить журнал в лист: при `.wait` и `.nothing` журнал не трогается,
    /// при `.show` сводка забирается ровно один раз.
    @MainActor
    static func makeItem(
        store: AppliedPlannedNoticeStore,
        readiness: Readiness
    ) -> AppliedPlannedNoticeItem? {
        guard decide(hasPendingNotice: store.hasPending, readiness: readiness) == .show,
              let digest = store.takeDigest() else { return nil }
        return AppliedPlannedNoticeItem(digest: digest)
    }
}
