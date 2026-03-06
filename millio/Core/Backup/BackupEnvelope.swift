import Foundation
import CryptoKit

struct BackupCompressionInfo: Codable {
    let algorithm: String
    let originalSize: Int
}

struct BackupKDFInfo: Codable {
    let algorithm: String
    let iterations: Int
    let saltBase64: String
}

struct BackupEncryptionInfo: Codable {
    let algorithm: String
    let kdf: BackupKDFInfo?
}

struct BackupEnvelopeHeader: Codable {
    /// Legacy envelope format without magic bytes or checksum. Kept for backward-compatible restore.
    static let legacyFormatVersion = 1
    /// Current envelope format with magic bytes and payload checksum.
    static let currentFormatVersion = 2
    
    let formatVersion: Int
    let metadata: BackupMetadata
    let compression: BackupCompressionInfo?
    let encryption: BackupEncryptionInfo?
    let payloadChecksumSHA256Base64: String?

    init(
        formatVersion: Int,
        metadata: BackupMetadata,
        compression: BackupCompressionInfo?,
        encryption: BackupEncryptionInfo?,
        payloadChecksumSHA256Base64: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.metadata = metadata
        self.compression = compression
        self.encryption = encryption
        self.payloadChecksumSHA256Base64 = payloadChecksumSHA256Base64
    }

    static func isSupportedFormatVersion(_ version: Int) -> Bool {
        version == legacyFormatVersion || version == currentFormatVersion
    }
}

enum BackupEnvelope {
    /// Magic prefix for current envelope format. Legacy format starts directly with the header length.
    private static let magicBytes = Data("MBKP".utf8)

    static func pack(header: BackupEnvelopeHeader, payload: Data) throws -> Data {
        if header.formatVersion <= BackupEnvelopeHeader.legacyFormatVersion {
            return try packLegacy(header: header, payload: payload)
        }

        let normalizedHeader = BackupEnvelopeHeader(
            formatVersion: header.formatVersion,
            metadata: header.metadata,
            compression: header.compression,
            encryption: header.encryption,
            payloadChecksumSHA256Base64: checksumBase64(for: payload)
        )
        let headerData = try encodeHeader(normalizedHeader)

        var result = Data()
        result.append(magicBytes)
        appendHeaderLength(headerData.count, to: &result)
        result.append(headerData)
        result.append(payload)
        return result
    }
    
    static func unpack(_ data: Data) throws -> (BackupEnvelopeHeader, Data) {
        if hasMagicPrefix(data) {
            return try unpackCurrent(data)
        }

        return try unpackLegacy(data)
    }
    
    static func looksLikeEnvelope(_ data: Data) -> Bool {
        if hasMagicPrefix(data) {
            let prefixLength = magicBytes.count
            guard data.count >= prefixLength + 5 else { return false }
            guard let headerLengthU32 = data.readUInt32BE(at: prefixLength) else { return false }
            let headerLength = Int(headerLengthU32)
            guard headerLength > 1, data.count >= prefixLength + 4 + headerLength else { return false }
            return data[data.startIndex.advanced(by: prefixLength + 4)] == UInt8(ascii: "{")
        }

        guard data.count >= 5 else { return false }
        guard let headerLengthU32 = data.readUInt32BE(at: 0) else { return false }
        let headerLength = Int(headerLengthU32)
        guard headerLength > 1, headerLength <= data.count - 4 else { return false }
        return data[data.startIndex.advanced(by: 4)] == UInt8(ascii: "{")
    }

    private static func packLegacy(header: BackupEnvelopeHeader, payload: Data) throws -> Data {
        let legacyHeader = BackupEnvelopeHeader(
            formatVersion: header.formatVersion,
            metadata: header.metadata,
            compression: header.compression,
            encryption: header.encryption,
            payloadChecksumSHA256Base64: nil
        )
        let headerData = try encodeHeader(legacyHeader)

        var result = Data()
        appendHeaderLength(headerData.count, to: &result)
        result.append(headerData)
        result.append(payload)
        return result
    }

    private static func unpackLegacy(_ data: Data) throws -> (BackupEnvelopeHeader, Data) {
        guard data.count >= 4 else { throw AppError.backupCorrupted }
        guard let headerLengthU32 = data.readUInt32BE(at: 0) else { throw AppError.backupCorrupted }
        let headerLength = Int(headerLengthU32)
        guard headerLength > 0, data.count >= 4 + headerLength else { throw AppError.backupCorrupted }

        let headerData = data.subdata(in: 4..<(4 + headerLength))
        let header = try JSONDecoder().decode(BackupEnvelopeHeader.self, from: headerData)
        let payload = data.suffix(from: 4 + headerLength)
        return (header, payload)
    }

    private static func unpackCurrent(_ data: Data) throws -> (BackupEnvelopeHeader, Data) {
        let prefixLength = magicBytes.count
        guard data.count >= prefixLength + 4 else { throw AppError.backupCorrupted }
        guard let headerLengthU32 = data.readUInt32BE(at: prefixLength) else { throw AppError.backupCorrupted }
        let headerLength = Int(headerLengthU32)
        let headerStart = prefixLength + 4
        let payloadStart = headerStart + headerLength

        guard headerLength > 0, data.count >= payloadStart else { throw AppError.backupCorrupted }

        let headerData = data.subdata(in: headerStart..<payloadStart)
        let header = try JSONDecoder().decode(BackupEnvelopeHeader.self, from: headerData)
        let payload = data.suffix(from: payloadStart)

        if header.formatVersion >= BackupEnvelopeHeader.currentFormatVersion {
            guard let checksum = header.payloadChecksumSHA256Base64,
                  checksum == checksumBase64(for: payload) else {
                throw AppError.backupCorrupted
            }
        }

        return (header, payload)
    }

    private static func encodeHeader(_ header: BackupEnvelopeHeader) throws -> Data {
        let headerData = try JSONEncoder().encode(header)
        guard headerData.count <= Int(UInt32.max) else {
            throw BackupFailureCode.envelopeHeaderTooLarge.appError
        }
        return headerData
    }

    private static func appendHeaderLength(_ count: Int, to data: inout Data) {
        var length = UInt32(count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    }

    private static func hasMagicPrefix(_ data: Data) -> Bool {
        data.starts(with: magicBytes)
    }

    private static func checksumBase64(for data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }
}
