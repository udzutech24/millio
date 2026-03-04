import Foundation

enum BackupJSON {
    static func decodeExportedDict(_ data: Data, typeName: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw BackupFailureCode.modelExportUnexpectedFormat(typeName).appError
        }
        return dict
    }
}
