//
//  HintsVisibilityPrefs.swift
//  millio
//
//  Простая прослойка над UserDefaults для скрываемых подсказок.
//
//  Зачем не @AppStorage:
//  - проще тестировать (можно подменить suite),
//  - можно централизовать формат ключей,
//  - UI остаётся декларативным: хранит локальный @State и пишет в prefs по нажатию.
//

import Foundation

struct HintsVisibilityPrefs {
    private let defaults: UserDefaults
    private let key: String

    init(key: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "hints.hidden.\(key)"
    }

    var isHidden: Bool {
        defaults.bool(forKey: key)
    }

    func setHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: key)
    }
}

