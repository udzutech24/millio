import Foundation

/// Детерминированный дефолт оформления счёта: цвет-акцент подбирается из палитры по стабильному
/// ключу счёта, одинаково при каждом запуске.
///
/// **Почему это не backfill строк `AccountAppearance`.** Строка в сторе нужна только там, где
/// пользователь что-то выбрал сам. Вычисляемый дефолт даёт на экране тот же результат — новый вид
/// сразу на ВСЕХ существующих счетах, — но без записи в БД: не растёт бэкап, не появляются строки
/// «оформление, которого владелец не задавал» (их пришлось бы отличать от заданных руками при
/// сбросе), и `purgeOrphanAccountAppearances` нечего стирать. Идемпотентность здесь не
/// обеспечивается флагом, а следует из чистой функции.
enum AccountAppearanceDefaults {

    /// Красный и серый исключены из авто-подбора: красный в списке зарезервирован за долгом
    /// (`AccountIconBadgeView.isError`), серый читается как «счёт выключен/архивный».
    /// В ручном выборе (`AccountIconPickerSheet`) оба остаются доступны.
    static let autoPalette: [String] = AccountIconSet.palette
        .filter { $0.id != "red" && $0.id != "gray" }
        .map(\.hex)

    /// `nil` только для пустого ключа — счёт без идентификатора получает прежний градиент.
    static func tintHex(forKey key: String) -> String? {
        guard !key.isEmpty, !autoPalette.isEmpty else { return nil }
        let index = Int(fnv1a(key) % UInt64(autoPalette.count))
        return autoPalette[index]
    }

    static func tintHex(for id: UUID) -> String? {
        tintHex(forKey: id.uuidString)
    }

    /// FNV-1a, а НЕ `Hasher`/`hashValue`: стандартный хеш Swift солится случайным seed'ом на каждый
    /// запуск процесса — цвет счёта менялся бы после каждого перезапуска приложения.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
