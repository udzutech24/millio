//
//  BackupFileFormat.swift
//  millio
//

import Foundation
import UniformTypeIdentifiers

/// Единственный источник правды о расширениях файла бэкапа.
enum BackupFileFormat {
    /// Расширение, с которым файлы экспортируются сейчас.
    static let preferredExtension = "milliobackup"

    /// Историческое расширение: файлы старых сборок (и объявление UTType в Info.plist) используют его.
    /// Принимать обязаны оба — иначе реальный файл владельца (`…v1.9.milliobackup`) не открывается.
    static let legacyExtension = "millio-backup"

    static let recognizedExtensions = [preferredExtension, legacyExtension]

    static let defaultExportFilename = "millio-backup.\(preferredExtension)"

    static let contentType = UTType(exportedAs: "com.alekseya.millio.backup", conformingTo: .data)

    /// Типы, которые принимает `fileImporter`. `.data` оставлен намеренно: Files отдаёт файл с
    /// неизвестным системе расширением как generic data, и без этого пункт «Восстановить из файла»
    /// показывал бы файл владельца недоступным (серым).
    static let importerContentTypes: [UTType] = [contentType, .data]

    static func isBackupFile(_ url: URL) -> Bool {
        recognizedExtensions.contains(url.pathExtension.lowercased())
    }
}
