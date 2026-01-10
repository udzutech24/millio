//
//  LocalizedStringKey+Extension.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

extension LocalizedStringKey {
    static func localized(_ key: String, bundle: Bundle = .main) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }
}
