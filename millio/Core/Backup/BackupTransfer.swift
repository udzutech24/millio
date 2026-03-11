//
//  BackupTransfer.swift
//  millio
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackupTransferPayload: Equatable {
    let fileName: String
    let data: Data
    let versionInfo: BackupVersionInfo
}

struct BackupTransferFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.millioBackup, .data] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw AppError.backupFailed("Backup file is empty")
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static var millioBackup: UTType {
        UTType(exportedAs: "com.alekseya.millio.backup", conformingTo: .data)
    }
}
