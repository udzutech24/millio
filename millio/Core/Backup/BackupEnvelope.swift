import Foundation

struct BackupCompressionInfo: Codable {
    let algorithm: String
    let originalSize: Int
}

struct BackupEncryptionInfo: Codable {
    let algorithm: String
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
        
        let headerLength: Int = data.prefix(4).withUnsafeBytes { rawBufferPointer in
            let value = rawBufferPointer.load(as: UInt32.self)
            return Int(UInt32(bigEndian: value))
        }
        
        guard headerLength > 0, data.count >= 4 + headerLength else { throw AppError.backupCorrupted }
        
        let headerData = data.subdata(in: 4..<(4 + headerLength))
        let header = try JSONDecoder().decode(BackupEnvelopeHeader.self, from: headerData)
        let payload = data.suffix(from: 4 + headerLength)
        return (header, payload)
    }
}
