import Foundation

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
    static let currentFormatVersion = 1
    
    let formatVersion: Int
    let metadata: BackupMetadata
    let compression: BackupCompressionInfo?
    let encryption: BackupEncryptionInfo?
}

enum BackupEnvelope {
    static func pack(header: BackupEnvelopeHeader, payload: Data) throws -> Data {
        let headerData = try JSONEncoder().encode(header)
        
        guard headerData.count <= Int(UInt32.max) else {
            throw AppError.backupFailed("Слишком большой заголовок backup")
        }
        
        var result = Data()
        var length = UInt32(headerData.count).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(headerData)
        result.append(payload)
        return result
    }
    
    static func unpack(_ data: Data) throws -> (BackupEnvelopeHeader, Data) {
        guard data.count >= 4 else { throw AppError.backupCorrupted }
        
        guard let headerLengthU32 = data.readUInt32BE(at: 0) else { throw AppError.backupCorrupted }
        let headerLength = Int(headerLengthU32)
        
        guard headerLength > 0, data.count >= 4 + headerLength else { throw AppError.backupCorrupted }
        
        let headerData = data.subdata(in: 4..<(4 + headerLength))
        let header = try JSONDecoder().decode(BackupEnvelopeHeader.self, from: headerData)
        let payload = data.suffix(from: 4 + headerLength)
        return (header, payload)
    }
    
    static func looksLikeEnvelope(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }
        guard let headerLengthU32 = data.readUInt32BE(at: 0) else { return false }
        let headerLength = Int(headerLengthU32)
        guard headerLength > 1, headerLength <= data.count - 4 else { return false }
        return data[data.startIndex.advanced(by: 4)] == UInt8(ascii: "{")
    }
}
