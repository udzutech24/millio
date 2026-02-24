//
//  CurrencyFlags.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Маппинг валют к флагам эмодзи
enum CurrencyFlags {
    /// Словарь валют -> флаги
    static let flags: [String: String] = [
        // Популярные валюты
        "RUB": "🇷🇺", // Российский рубль
        "USD": "🇺🇸", // Доллар США
        "EUR": "🇪🇺", // Евро
        "GBP": "🇬🇧", // Британский фунт
        "JPY": "🇯🇵", // Японская иена
        "CNY": "🇨🇳", // Китайский юань
        "KRW": "🇰🇷", // Южнокорейская вона
        "INR": "🇮🇳", // Индийская рупия
        "BRL": "🇧🇷", // Бразильский реал
        "MXN": "🇲🇽", // Мексиканское песо
        "CAD": "🇨🇦", // Канадский доллар
        "AUD": "🇦🇺", // Австралийский доллар
        "NZD": "🇳🇿", // Новозеландский доллар
        "CHF": "🇨🇭", // Швейцарский франк
        "SEK": "🇸🇪", // Шведская крона
        "NOK": "🇳🇴", // Норвежская крона
        "DKK": "🇩🇰", // Датская крона
        "PLN": "🇵🇱", // Польский злотый
        "CZK": "🇨🇿", // Чешская крона
        "HUF": "🇭🇺", // Венгерский форинт
        "RON": "🇷🇴", // Румынский лей
        "BGN": "🇧🇬", // Болгарский лев
        "HRK": "🇭🇷", // Хорватская куна
        "TRY": "🇹🇷", // Турецкая лира
        "ILS": "🇮🇱", // Израильский шекель
        "AED": "🇦🇪", // Дирхам ОАЭ
        "SAR": "🇸🇦", // Саудовский риял
        "QAR": "🇶🇦", // Катарский риал
        "KWD": "🇰🇼", // Кувейтский динар
        "BHD": "🇧🇭", // Бахрейнский динар
        "OMR": "🇴🇲", // Оманский риал
        "JOD": "🇯🇴", // Иорданский динар
        "EGP": "🇪🇬", // Египетский фунт
        "ZAR": "🇿🇦", // Южноафриканский рэнд
        "NGN": "🇳🇬", // Нигерийская найра
        "KES": "🇰🇪", // Кенийский шиллинг
        "GHS": "🇬🇭", // Ганский седи
        "ETB": "🇪🇹", // Эфиопский быр
        "TZS": "🇹🇿", // Танзанийский шиллинг
        "UGX": "🇺🇬", // Угандийский шиллинг
        "RWF": "🇷🇼", // Руандский франк
        "MAD": "🇲🇦", // Марокканский дирхам
        "TND": "🇹🇳", // Тунисский динар
        "DZD": "🇩🇿", // Алжирский динар
        "LYD": "🇱🇾", // Ливийский динар
        "SDG": "🇸🇩", // Суданский фунт
        "SOS": "🇸🇴", // Сомалийский шиллинг
        "DJF": "🇩🇯", // Джибутийский франк
        "ERN": "🇪🇷", // Эритрейская накфа
        "KZT": "🇰🇿", // Казахстанский тенге
        "UZS": "🇺🇿", // Узбекский сум
        "KGS": "🇰🇬", // Киргизский сом
        "TJS": "🇹🇯", // Таджикский сомони
        "TMT": "🇹🇲", // Туркменский манат
        "AZN": "🇦🇿", // Азербайджанский манат
        "AMD": "🇦🇲", // Армянский драм
        "GEL": "🇬🇪", // Грузинский лари
        "UAH": "🇺🇦", // Украинская гривна
        "BYN": "🇧🇾", // Белорусский рубль
        "MDL": "🇲🇩", // Молдавский лей
        "BAM": "🇧🇦", // Конвертируемая марка Боснии и Герцеговины
        "RSD": "🇷🇸", // Сербский динар
        "MKD": "🇲🇰", // Македонский денар
        "ALL": "🇦🇱", // Албанский лек
        "ISK": "🇮🇸", // Исландская крона
        "THB": "🇹🇭", // Тайский бат
        "SGD": "🇸🇬", // Сингапурский доллар
        "MYR": "🇲🇾", // Малайзийский ринггит
        "IDR": "🇮🇩", // Индонезийская рупия
        "PHP": "🇵🇭", // Филиппинское песо
        "VND": "🇻🇳", // Вьетнамский донг
        "MMK": "🇲🇲", // Мьянманский кьят
        "LAK": "🇱🇦", // Лаосский кип
        "KHR": "🇰🇭", // Камбоджийский риель
        "BDT": "🇧🇩", // Бангладешская така
        "PKR": "🇵🇰", // Пакистанская рупия
        "LKR": "🇱🇰", // Шри-ланкийская рупия
        "NPR": "🇳🇵", // Непальская рупия
        "AFN": "🇦🇫", // Афганский афгани
        "IRR": "🇮🇷", // Иранский риал
        "IQD": "🇮🇶", // Иракский динар
        "SYP": "🇸🇾", // Сирийский фунт
        "LBP": "🇱🇧", // Ливанский фунт
        "YER": "🇾🇪", // Йеменский риал
        "BND": "🇧🇳", // Брунейский доллар
        "FJD": "🇫🇯", // Фиджийский доллар
        "PGK": "🇵🇬", // Папуа-новогвинейская кина
        "SBD": "🇸🇧", // Доллар Соломоновых Островов
        "VUV": "🇻🇺", // Вануатский вату
        "WST": "🇼🇸", // Самоанская тала
        "TOP": "🇹🇴", // Тонганская паанга
        "XPF": "🇵🇫", // Французский тихоокеанский франк (CFP)
        "NIO": "🇳🇮", // Никарагуанская кордоба
        "GTQ": "🇬🇹", // Гватемальский кетсаль
        "BZD": "🇧🇿", // Белизский доллар
        "HNL": "🇭🇳", // Гондурасская лемпира
        "SVC": "🇸🇻", // Сальвадорский колон
        "CRC": "🇨🇷", // Костариканский колон
        "PAB": "🇵🇦", // Панамский бальбоа
        "COP": "🇨🇴", // Колумбийское песо
        "VES": "🇻🇪", // Венесуэльский боливар
        "GYD": "🇬🇾", // Гайанский доллар
        "SRD": "🇸🇷", // Суринамский доллар
        "TTD": "🇹🇹", // Доллар Тринидада и Тобаго
        "BBD": "🇧🇧", // Барбадосский доллар
        "XCD": "🇦🇬", // Восточно-карибский доллар
        "AWG": "🇦🇼", // Арубанский флорин
        "ANG": "🇨🇼", // Нидерландский антильский гульден
        "CLP": "🇨🇱", // Чилийское песо
        "BOB": "🇧🇴", // Боливийский боливиано
        "PEN": "🇵🇪", // Перуанский соль
        "PYG": "🇵🇾", // Парагвайский гуарани
        "UYU": "🇺🇾", // Уругвайский песо
        "ARS": "🇦🇷", // Аргентинское песо
        "FKP": "🇫🇰", // Фунт Фолклендских островов
        "GIP": "🇬🇮", // Гибралтарский фунт
        "SHP": "🇸🇭", // Фунт Святой Елены
        "GGP": "🇬🇬", // Гернсийский фунт
        "JEP": "🇯🇪", // Джерсийский фунт
        "IMP": "🇮🇲", // Фунт острова Мэн
        "IEP": "🇮🇪", // Ирландский фунт (исторический)
        "LTL": "🇱🇹", // Литовский лит (исторический)
        "LVL": "🇱🇻", // Латвийский лат (исторический)
        "EEK": "🇪🇪", // Эстонская крона (исторический)
        "SKK": "🇸🇰", // Словацкая крона (исторический)
        "SIT": "🇸🇮", // Словенский толар (исторический)
        "MZM": "🇲🇿", // Мозамбикский метикал (старый)
        "ZWL": "🇿🇼", // Зимбабвийский доллар
        "ZWD": "🇿🇼", // Зимбабвийский доллар (старый)
        "XOF": "🇸🇳", // Западноафриканский франк (CFA)
        "XAF": "🇨🇲", // Центральноафриканский франк (CFA)
        "XDR": "🌍", // Специальные права заимствования (SDR)
        "XAU": "🥇", // Золото
        "XAG": "🥈", // Серебро
        "XPT": "💎", // Платина
        "XPD": "💠", // Палладий
    ]
    
    /// Получить флаг для валюты
    static func flag(for currencyCode: String) -> String {
        let code = currencyCode.uppercased()
        // Сначала проверяем явный список
        if let explicitFlag = flags[code] {
            return explicitFlag
        }
        // Затем пытаемся найти регион для валюты и сгенерировать флаг
        if let region = CurrencySelectionSupport.currencyToRegion(for: code) {
            return generateFlagEmoji(fromRegionCode: region)
        }
        return "🏳️" // Флаг по умолчанию
    }

    /// Возвращает имя ассета флага из Assets.xcassets/Icons/Flags.
    /// Для большинства валют берется регион, связанный с кодом валюты.
    /// Если ассет не найден, возвращается fallback-иконка "xx".
    static func assetName(for currencyCode: String) -> String? {
        let code = currencyCode.uppercased()
        guard !CurrencySelectionSupport.isCrypto(code) else { return nil }

        if let explicitFlag = flags[code],
           let explicitRegion = regionCode(fromFlagEmoji: explicitFlag),
           hasAsset(named: explicitRegion.lowercased()) {
            return explicitRegion.lowercased()
        }

        if let regionCode = CurrencySelectionSupport.currencyToRegion(for: code)?.lowercased(),
           hasAsset(named: regionCode) {
            return regionCode
        }

        let fallbackByCurrencyCode = code.lowercased()
        if hasAsset(named: fallbackByCurrencyCode) {
            return fallbackByCurrencyCode
        }

        if hasAsset(named: "xx") {
            return "xx"
        }

        return nil
    }
    
    /// Генерация флага эмодзи из кода региона (2 буквы)
    private static func generateFlagEmoji(fromRegionCode regionCode: String) -> String {
        let rc = regionCode.uppercased()
        guard rc.count == 2 else { return "🏳️" }
        let base: UInt32 = 0x1F1E6
        let a = UnicodeScalar("A").value
        
        var scalars: [UnicodeScalar] = []
        for ch in rc.unicodeScalars {
            let v = ch.value
            guard v >= a, v <= UnicodeScalar("Z").value else { return "🏳️" }
            let indicator = base + (v - a)
            if let s = UnicodeScalar(indicator) { scalars.append(s) }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func regionCode(fromFlagEmoji emoji: String) -> String? {
        let indicators = Array(emoji.unicodeScalars.filter { scalar in
            scalar.value >= 0x1F1E6 && scalar.value <= 0x1F1FF
        })
        guard indicators.count == 2 else { return nil }

        let aScalar = UnicodeScalar("A").value
        let first = indicators[0].value - 0x1F1E6 + aScalar
        let second = indicators[1].value - 0x1F1E6 + aScalar

        guard let firstLetter = UnicodeScalar(first), let secondLetter = UnicodeScalar(second) else {
            return nil
        }

        return String(firstLetter) + String(secondLetter)
    }

    private static func hasAsset(named name: String) -> Bool {
#if canImport(UIKit)
        return UIImage(named: name) != nil
#elseif canImport(AppKit)
        return NSImage(named: NSImage.Name(name)) != nil
#else
        return false
#endif
    }
}
