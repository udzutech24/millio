import Foundation
import SwiftData

/// Единственная точка доступа к `AccountAppearance`: один fetch на экран → словарь по `accountID`.
///
/// Запросы из тела `View` запрещены: список счетов рисует десятки строк, и `@Query`/fetch на строку
/// дал бы N+1 обращений к стору на каждый перерисованный кадр.
@MainActor
struct AccountAppearanceStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Словарь `accountID → оформление`. Дубли по одному счёту схлопываются (последний `updatedAt`
    /// побеждает): `@Attribute(.unique)` в проекте запрещён, а restore/merge может внести вторую
    /// строку на тот же счёт.
    func loadAll() throws -> [UUID: AccountAppearance] {
        let rows = try context.fetch(FetchDescriptor<AccountAppearance>())
        return rows.reduce(into: [UUID: AccountAppearance]()) { result, row in
            if let existing = result[row.accountID], existing.updatedAt >= row.updatedAt { return }
            result[row.accountID] = row
        }
    }

    /// Тот же один fetch, что `loadAll`, но наружу отдаются значения, а не `@Model`.
    /// Это единственный способ снабдить список счетов оформлением: точечный запрос из тела строки
    /// дал бы N обращений к стору на каждый кадр при 60+ счетах.
    func loadSnapshots() throws -> [UUID: AccountAppearanceSnapshot] {
        try loadAll().mapValues(AccountAppearanceSnapshot.init)
    }

    func favoriteAccountIDs() throws -> Set<UUID> {
        Set(try loadAll().filter { $0.value.isFavorite }.keys)
    }

    func appearance(for accountID: UUID) throws -> AccountAppearance? {
        try existingRows(for: accountID).first
    }

    /// Идемпотентный upsert: два вызова на один `accountID` дают одну строку.
    @discardableResult
    func upsert(accountID: UUID, _ mutate: (AccountAppearance) -> Void) throws -> AccountAppearance {
        let rows = try existingRows(for: accountID)
        let target: AccountAppearance
        if let existing = rows.first {
            target = existing
            // Схлопываем дубли по ходу дела — иначе следующий loadAll снова выберет «победителя»
            // произвольно и правка визуально «не применится».
            for duplicate in rows.dropFirst() { context.delete(duplicate) }
        } else {
            target = AccountAppearance(accountID: accountID)
            context.insert(target)
        }
        mutate(target)
        target.updatedAt = Date()
        return target
    }

    /// Явный выбор пользователя (иконка/цвет). Полный сброс — обе величины nil и счёт не в
    /// избранном — удаляет строку: счёт возвращается к ВЫЧИСЛЯЕМОМУ дефолту
    /// (`AccountAppearanceDefaults`), а не хранит пустое оформление.
    ///
    /// `presetRaw` и `tintHex` взаимоисключающи по контракту вызывающей стороны
    /// (`AccountIconPickerSheet`): дизайн задаёт свой акцент, ручной цвет его перебивает. Стор
    /// пишет то, что дали, а порядок разрешения при обоих заполненных полях один и описан в
    /// `CashflowAccountPickerDetailsFactory.resolvedAppearance`.
    @discardableResult
    func setAppearance(
        accountID: UUID,
        iconName: String?,
        tintHex: String?,
        presetRaw: String? = nil
    ) throws -> Bool {
        let row = try upsert(accountID: accountID) {
            $0.iconName = iconName
            $0.tintHex = tintHex
            $0.presetRaw = presetRaw
        }
        if row.isDefault {
            context.delete(row)
            return false
        }
        return true
    }

    @discardableResult
    func toggleFavorite(accountID: UUID) throws -> Bool {
        let row = try upsert(accountID: accountID) { $0.isFavorite.toggle() }
        // Снятая звезда на строке без оформления не должна оставлять пустую запись в сторе.
        if row.isDefault {
            context.delete(row)
            return false
        }
        return row.isFavorite
    }

    func isFavorite(accountID: UUID) throws -> Bool {
        try appearance(for: accountID)?.isFavorite ?? false
    }

    /// Строки, отсортированные так, что первой идёт самая свежая — тот же победитель, что в `loadAll`.
    private func existingRows(for accountID: UUID) throws -> [AccountAppearance] {
        var descriptor = FetchDescriptor<AccountAppearance>(
            predicate: #Predicate<AccountAppearance> { $0.accountID == accountID }
        )
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }
}
