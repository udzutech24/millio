import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф2: каталог дизайнов счёта, PRO-гейт и их влияние на общий резолвер оформления.
/// Проверяем логику (каталог, политика, приоритет, персистентность), не рендеринг галереи.
@Suite(.serialized)
@MainActor
struct AccountAppearancePresetTests {

    // MARK: - Каталог

    @Test("Каталог непустой, id уникальны, у каждого пресета валидный градиент из двух hex")
    func catalogIntegrity() {
        let presets = AccountAppearancePreset.allCases
        #expect(!presets.isEmpty)
        #expect(Set(presets.map(\.rawValue)).count == presets.count)

        for preset in presets {
            #expect(preset.gradientHexes.count == 2)
            for hex in preset.gradientHexes {
                #expect(hex.hasPrefix("#"))
                #expect(hex.count == 7)
                #expect(hex.dropFirst().allSatisfy { $0.isHexDigit })
            }
            #expect(preset.accentHex == preset.gradientHexes[0])
            #expect(preset.titleKey == "account.appearance.preset.\(preset.rawValue)")
        }
    }

    @Test("Неизвестный presetRaw из чужого бэкапа резолвится в nil, а не роняет экран")
    func unknownPresetResolvesToNil() {
        #expect(AccountAppearancePreset.resolve("preset-from-the-future") == nil)
        #expect(AccountAppearancePreset.resolve(nil) == nil)
        #expect(AccountAppearancePreset.resolve("ocean") == .ocean)
    }

    // MARK: - PRO-гейт (единственный источник — EntitlementPolicy)

    @Test("Галерея — PRO-фича: Free не получает, PRO получает")
    func galleryIsProOnly() {
        #expect(EntitlementPolicy.isAccountAppearanceGalleryProOnly)
        #expect(EntitlementPolicy.canUseAccountAppearanceGallery(isPro: false) == false)
        #expect(EntitlementPolicy.canUseAccountAppearanceGallery(isPro: true))
    }

    // MARK: - Резолвер: приоритет источников цвета

    @Test("Дизайн даёт акцент бейджа, когда ручного цвета нет")
    func presetProvidesAccent() {
        let resolved = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: UUID().uuidString,
            name: "Вклад",
            appearance: AccountAppearanceSnapshot(presetRaw: AccountAppearancePreset.gold.rawValue)
        )
        #expect(resolved.iconColorHex == AccountAppearancePreset.gold.accentHex)
    }

    @Test("Ручной цвет сильнее дизайна: бэкап с обоими полями не даёт разнобоя")
    func manualTintBeatsPreset() {
        let resolved = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: UUID().uuidString,
            name: "Карта",
            appearance: AccountAppearanceSnapshot(
                tintHex: "#123456",
                presetRaw: AccountAppearancePreset.ocean.rawValue
            )
        )
        #expect(resolved.iconColorHex == "#123456")
    }

    @Test("Дизайн сильнее легаси-полей карты, но неизвестный дизайн откатывается к ним")
    func presetBeatsLegacyAndUnknownFallsBack() {
        let key = UUID().uuidString
        let withPreset = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: "Карта",
            appearance: AccountAppearanceSnapshot(presetRaw: AccountAppearancePreset.violet.rawValue),
            legacyIconColorHex: "#ABCDEF"
        )
        #expect(withPreset.iconColorHex == AccountAppearancePreset.violet.accentHex)

        let unknown = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: "Карта",
            appearance: AccountAppearanceSnapshot(presetRaw: "нет-такого"),
            legacyIconColorHex: "#ABCDEF"
        )
        #expect(unknown.iconColorHex == "#ABCDEF")
    }

    @Test("Без дизайна и без выбора счёт остаётся на детерминированном дефолте")
    func noPresetKeepsDeterministicDefault() {
        let key = UUID().uuidString
        let resolved = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: "Наличные",
            appearance: AccountAppearanceSnapshot()
        )
        #expect(resolved.iconColorHex == AccountAppearanceDefaults.tintHex(forKey: key))
    }

    // MARK: - Персистентность выбора

    @Test("Выбор дизайна переживает перезагрузку среза и пишется через стор (upsert, одна строка)")
    func presetSurvivesReload() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = AccountAppearanceStore(context: context)
        let accountID = UUID()

        try store.setAppearance(
            accountID: accountID,
            iconName: nil,
            tintHex: nil,
            presetRaw: AccountAppearancePreset.mint.rawValue
        )
        try context.save()

        #expect(try context.fetch(FetchDescriptor<AccountAppearance>()).count == 1)
        let snapshots = try store.loadSnapshots()
        #expect(snapshots[accountID]?.presetRaw == AccountAppearancePreset.mint.rawValue)
    }

    @Test("Сброс дизайна удаляет строку: счёт возвращается к вычисляемому дефолту, мусора нет")
    func resettingPresetRemovesRow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = AccountAppearanceStore(context: context)
        let accountID = UUID()

        try store.setAppearance(
            accountID: accountID,
            iconName: nil,
            tintHex: nil,
            presetRaw: AccountAppearancePreset.ember.rawValue
        )
        try store.setAppearance(accountID: accountID, iconName: nil, tintHex: nil, presetRaw: nil)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<AccountAppearance>()).isEmpty)
    }

    @Test("Избранное дизайном не стирается: сброс дизайна оставляет звезду")
    func resettingPresetKeepsFavorite() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = AccountAppearanceStore(context: context)
        let accountID = UUID()

        try store.toggleFavorite(accountID: accountID)
        try store.setAppearance(accountID: accountID, iconName: nil, tintHex: nil, presetRaw: nil)
        try context.save()

        #expect(try store.isFavorite(accountID: accountID))
    }

    @Test("Строка с дизайном не считается пустой — иначе выбор пользователя стирался бы сразу")
    func presetRowIsNotDefault() {
        let row = AccountAppearance(
            accountID: UUID(),
            presetRaw: AccountAppearancePreset.forest.rawValue
        )
        #expect(row.isDefault == false)
    }

    @Test("Все названия дизайнов локализованы в ru/en/zh-Hans")
    func presetTitlesAreLocalized() throws {
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.localizableURL())
        ) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])

        var keys = AccountAppearancePreset.allCases.map(\.titleKey)
        keys.append(contentsOf: [
            "account.appearance.preset.none",
            "account.icon_picker.tab.design",
            "account.appearance.gallery.locked",
            "account.appearance.gallery.pro_title",
            "account.appearance.gallery.pro_message",
        ])

        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "нет ключа \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "нет переводов \(key)")
            for language in ["ru", "en", "zh-Hans"] {
                #expect(localizations[language] != nil, "нет \(language) для \(key)")
            }
        }
    }

    /// Каталог строк читаем из ИСХОДНИКА, а не из бандла: тест обязан падать на непереведённом
    /// ключе даже до пересборки ресурсов.
    private static func localizableURL() -> URL {
        var baseURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = baseURL.appendingPathComponent("millio/Localizable.xcstrings")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            baseURL.deleteLastPathComponent()
        }
        return baseURL.appendingPathComponent("millio/Localizable.xcstrings")
    }
}
