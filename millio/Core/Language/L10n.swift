//
//  L10n.swift
//  millio
//
//  Глобальная обёртка для String(localized:) с явным bundle текущего языка.
//  Нужна потому что на iOS 16+ String(localized:) с .xcstrings-каталогом
//  резолвится через StringCatalog runtime и обходит ObjC Bundle swizzling.
//  Явный параметр bundle: гарантирует правильный языковой bundle.
//
//  Использование:
//    L("key")                          вместо String(localized: "key")
//    L("key", defaultValue: "Default") вместо String(localized: "key", defaultValue: "Default")
//

import Foundation

/// Возвращает локализованную строку из языкового bundle текущего языка приложения.
/// Аналог `String(localized: key)` с явным `bundle: LanguageManager.shared.currentBundle`.
@inline(__always)
func L(_ key: String.LocalizationValue, table: String? = nil) -> String {
    String(localized: key, table: table, bundle: LanguageManager.shared.currentBundle)
}

/// Перегрузка с `defaultValue` — для мест, где ключ может отсутствовать в каталоге.
/// Принимает String-ключ (string literal) и fallback-значение.
/// `comment` намеренно опущен: он используется только компилятором и не имеет
/// смысла в runtime-вызове.
@inline(__always)
func L(_ key: String, defaultValue: String, table: String? = nil) -> String {
    // NSLocalizedString поддерживает value (defaultValue) и explicit bundle
    NSLocalizedString(key, tableName: table, bundle: LanguageManager.shared.currentBundle, value: defaultValue, comment: "")
}
