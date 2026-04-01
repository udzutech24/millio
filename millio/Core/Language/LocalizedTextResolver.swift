//
//  LocalizedTextResolver.swift
//  millio
//
//  Created by Codex on 31.03.2026.
//

import Foundation

/// Resolves user-facing copy lazily against the active app locale instead of
/// caching already-rendered strings in state.
struct LocalizedTextResolver {
    private let resolver: (Locale) -> String

    init(_ resolver: @escaping (Locale) -> String) {
        self.resolver = resolver
    }

    func resolve(in locale: Locale) -> String {
        resolver(locale)
    }

    static let empty = LocalizedTextResolver { _ in "" }

    static func key(_ key: String, fallback: String? = nil, bundle: Bundle = AppLocalization.resourceBundle) -> LocalizedTextResolver {
        LocalizedTextResolver { locale in
            AppLocalization.string(key, locale: locale, fallback: fallback, bundle: bundle)
        }
    }
}
