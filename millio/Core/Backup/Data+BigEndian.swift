import Foundation

extension Data {
    func readUInt32BE(at offset: Int) -> UInt32? {
        let end = offset + 4
        guard offset >= 0, end <= count else { return nil }
        return withUnsafeBytes { rawBufferPointer in
            let base = rawBufferPointer.bindMemory(to: UInt8.self).baseAddress!
            let b0 = UInt32(base[offset])
            let b1 = UInt32(base[offset + 1])
            let b2 = UInt32(base[offset + 2])
            let b3 = UInt32(base[offset + 3])
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
    }
}
