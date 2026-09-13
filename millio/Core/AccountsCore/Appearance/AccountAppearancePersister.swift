import Foundation
import SwiftData

/// Best-effort запись оформления (избранное/иконка/цвет) сразу после создания счёта.
///
/// Вынесено из `FinanceAddAccountView+CoreCreate.swift` отдельным типом без зависимости от
/// `@State`/`View`: `@State`, заданный вне живого рендера SwiftUI (как в unit-тесте), не читается
/// обратно — `location` остаётся `nil`, и геттер всегда возвращает исходное значение по умолчанию
/// (проверено эмпирически). Чтобы Баг 2 (избранное/иконка/цвет молча терялись при создании ЛЮБОГО
/// типа счёта) не повторился незамеченным, решение о записи должно быть чистой функцией от явных
/// параметров, а не от состояния формы.
@MainActor
enum AccountAppearancePersister {
    /// No-op, если всё пусто/false — не плодит строку в сторе ради счёта без оформления
    /// (`AccountAppearance.isDefault`). Ошибка — best-effort и не должна ронять уже созданный счёт
    /// (offline-first: счёт важнее оформления), поэтому логируется тем же способом, что и остальные
    /// `catch` в `FinanceAddAccountView+CoreCreate.swift`, а не `fatalError`.
    static func persistIfNeeded(
        context: ModelContext,
        accountID: UUID,
        isFavorite: Bool,
        iconName: String?,
        tintHex: String?
    ) {
        guard isFavorite || iconName != nil || tintHex != nil else { return }
        do {
            try AccountAppearanceStore(context: context).upsert(accountID: accountID) {
                $0.isFavorite = isFavorite
                $0.iconName = iconName
                $0.tintHex = tintHex
            }
            // `upsert` только вставляет в контекст, не коммитит — в отличие от соседних
            // `FinanceViewModel.saveAppearance`/`toggleFavorite`, которые сами вызывают
            // `modelContext.save()`. Без этого звезда/иконка молча не переживали relaunch,
            // хотя счёт (сохранённый отдельным `save()` в `AccountProductFactory`) — переживал.
            //
            // Инвариант, на который это опирается: на момент вызова `persistIfNeeded` счёт из
            // `command` УЖЕ закоммичен фабрикой (`AccountsCoreSaveBoundary` внутри `factory.create`),
            // и между этим `create` и данным вызовом в `AccountCreationCoordinator` больше ничего
            // в контекст не вставляется. `save()` здесь коммитит ВЕСЬ контекст, а не только эту
            // строку — если когда-нибудь между `create` и `persistIfNeeded` появится ещё один
            // insert (для другой фичи), этот `save()` зафиксирует его раньше, чем рассчитывал
            // вызывающий код. Меняя это соседство — проверь этот комментарий.
            try context.save()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось сохранить оформление счёта нового ядра: \(error)")
        }
    }
}
