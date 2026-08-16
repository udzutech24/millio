import Foundation
import CryptoKit
import UniformTypeIdentifiers

public enum IncomingStatementFileKind: String, Codable, CaseIterable, Sendable {
    case csv
    case pdf
    case xlsx

    public var filenameExtension: String { rawValue }
}

public struct IncomingStatementManifest: Codable, Equatable, Identifiable, Sendable {
    public let version: Int
    public let id: UUID
    public let receivedAt: Date
    public let kind: IncomingStatementFileKind
    public let byteCount: Int64
    public let contentHash: String

    public init(
        version: Int = 1,
        id: UUID,
        receivedAt: Date,
        kind: IncomingStatementFileKind,
        byteCount: Int64,
        contentHash: String
    ) {
        self.version = version
        self.id = id
        self.receivedAt = receivedAt
        self.kind = kind
        self.byteCount = byteCount
        self.contentHash = contentHash
    }
}

public enum IncomingStatementFileError: Error, Equatable {
    case missingFile
    case notRegularFile
    case symbolicLink
    case empty
    case oversized
    case unsupportedType
    case signatureMismatch
    case invalidInbox
    case invalidManifest
}

public enum IncomingStatementFilePolicy {
    public static let maximumBytes: Int64 = 25 * 1_024 * 1_024
    public static let allowedTypes: [UTType] = [
        .commaSeparatedText,
        .pdf,
        UTType(filenameExtension: "xlsx") ?? .spreadsheet
    ]

    public static func validate(
        url: URL,
        declaredType: UTType?,
        fileManager: FileManager = .default
    ) throws -> (kind: IncomingStatementFileKind, byteCount: Int64, prefix: Data) {
        guard fileManager.fileExists(atPath: url.path) else { throw IncomingStatementFileError.missingFile }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentTypeKey
        ])
        guard values.isSymbolicLink != true else { throw IncomingStatementFileError.symbolicLink }
        guard values.isRegularFile == true else { throw IncomingStatementFileError.notRegularFile }
        let size = Int64(values.fileSize ?? 0)
        guard size > 0 else { throw IncomingStatementFileError.empty }
        guard size <= maximumBytes else { throw IncomingStatementFileError.oversized }

        let resolvedType = declaredType ?? values.contentType
        let kind = try resolveKind(url: url, declaredType: resolvedType)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 8_192) ?? Data()
        guard signatureMatches(kind: kind, prefix: prefix) else {
            throw IncomingStatementFileError.signatureMismatch
        }
        return (kind, size, prefix)
    }

    public static func resolveKind(url: URL, declaredType: UTType?) throws -> IncomingStatementFileKind {
        let ext = url.pathExtension.lowercased()
        let kind: IncomingStatementFileKind
        switch ext {
        case "csv": kind = .csv
        case "pdf": kind = .pdf
        case "xlsx": kind = .xlsx
        default: throw IncomingStatementFileError.unsupportedType
        }
        guard let declaredType else { throw IncomingStatementFileError.unsupportedType }
        let matches: Bool
        switch kind {
        case .csv: matches = declaredType.conforms(to: .commaSeparatedText) || declaredType.conforms(to: .plainText)
        case .pdf: matches = declaredType.conforms(to: .pdf)
        case .xlsx:
            let xlsx = UTType(filenameExtension: "xlsx") ?? .spreadsheet
            matches = declaredType.conforms(to: xlsx) || declaredType.conforms(to: .spreadsheet) || declaredType.conforms(to: .zip)
        }
        guard matches else { throw IncomingStatementFileError.unsupportedType }
        return kind
    }

    public static func signatureMatches(kind: IncomingStatementFileKind, prefix: Data) -> Bool {
        switch kind {
        case .pdf:
            return prefix.starts(with: Data("%PDF-".utf8))
        case .xlsx:
            return prefix.starts(with: Data([0x50, 0x4b, 0x03, 0x04]))
                || prefix.starts(with: Data([0x50, 0x4b, 0x05, 0x06]))
        case .csv:
            guard !prefix.isEmpty, !prefix.contains(0), String(data: prefix, encoding: .utf8) != nil else { return false }
            return true
        }
    }
}

public struct IncomingStatementInboxItem: Equatable, Identifiable, Sendable {
    public let manifest: IncomingStatementManifest
    public let fileURL: URL
    public var id: UUID { manifest.id }
}

public struct IncomingStatementInbox {
    public static let appGroupID = "group.com.millio.app"
    public static let directoryName = "StatementInbox"
    public static let retention: TimeInterval = 7 * 24 * 60 * 60

    private let directoryURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.now = now
    }

    public static func appGroup(fileManager: FileManager = .default) throws -> IncomingStatementInbox {
        guard let root = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw IncomingStatementFileError.invalidInbox
        }
        return .init(directoryURL: root.appendingPathComponent(directoryName, isDirectory: true), fileManager: fileManager)
    }

    public func enqueue(sourceURL: URL, declaredType: UTType?) throws -> IncomingStatementInboxItem {
        let validation = try IncomingStatementFilePolicy.validate(
            url: sourceURL,
            declaredType: declaredType,
            fileManager: fileManager
        )
        try prepareDirectory()
        let digest = try SHA256FileDigest.hex(url: sourceURL)
        if let existing = try queuedItems().first(where: { $0.manifest.contentHash == digest }) {
            return existing
        }

        let id = UUID()
        let finalURL = fileURL(id: id, kind: validation.kind)
        let temporaryURL = directoryURL.appendingPathComponent(".\(id.uuidString).partial")
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        try protect(temporaryURL)
        try fileManager.moveItem(at: temporaryURL, to: finalURL)
        try protect(finalURL)

        let manifest = IncomingStatementManifest(
            id: id,
            receivedAt: now(),
            kind: validation.kind,
            byteCount: validation.byteCount,
            contentHash: digest
        )
        let data = try JSONEncoder().encode(manifest)
        let manifestURL = self.manifestURL(id: id)
        try data.write(to: manifestURL, options: .atomic)
        try protect(manifestURL)
        return .init(manifest: manifest, fileURL: finalURL)
    }

    public func queuedItems() throws -> [IncomingStatementInboxItem] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let manifest = try? decoder.decode(IncomingStatementManifest.self, from: Data(contentsOf: url)),
                  manifest.version == 1 else { return nil }
            let file = fileURL(id: manifest.id, kind: manifest.kind)
            guard fileManager.fileExists(atPath: file.path) else { return nil }
            return .init(manifest: manifest, fileURL: file)
        }.sorted {
            if $0.manifest.receivedAt == $1.manifest.receivedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.manifest.receivedAt < $1.manifest.receivedAt
        }
    }

    public func discard(_ item: IncomingStatementInboxItem) throws {
        if fileManager.fileExists(atPath: item.fileURL.path) { try fileManager.removeItem(at: item.fileURL) }
        let manifest = manifestURL(id: item.id)
        if fileManager.fileExists(atPath: manifest.path) { try fileManager.removeItem(at: manifest) }
    }

    public func cleanupExpired() throws {
        let cutoff = now().addingTimeInterval(-Self.retention)
        for item in try queuedItems() where item.manifest.receivedAt < cutoff {
            try discard(item)
        }
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try protect(directoryURL)
    }

    private func fileURL(id: UUID, kind: IncomingStatementFileKind) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension(kind.filenameExtension)
    }

    private func manifestURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func protect(_ url: URL) throws {
        try (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }
}

private enum SHA256FileDigest {
    static func hex(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
