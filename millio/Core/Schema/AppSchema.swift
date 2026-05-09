//
//  AppSchema.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Схема SwiftData для приложения.
/// Единственный источник правды — AppSchemaCurrent.models (= AppSchemaV_N.models).
/// ModelTypeRegistry используется только для backup/restore, не для построения схемы.
struct AppSchema {
    static func create() -> Schema {
        Schema(AppSchemaCurrent.models, version: AppSchemaCurrent.versionIdentifier)
    }
}
