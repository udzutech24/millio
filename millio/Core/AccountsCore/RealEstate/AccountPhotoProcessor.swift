import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AccountPhotoProcessorError: Error, Equatable {
    case emptyData
    case invalidImage
    case outputTooLarge
}

struct AccountPhotoProcessor: Sendable {
    static let maximumPixelDimension = 2_048
    static let maximumEncodedBytes = 2_500_000

    /// Decodes and re-encodes off the main actor. Re-encoding from pixels deliberately drops
    /// source EXIF/GPS metadata instead of copying the source property dictionary.
    func process(_ sourceData: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard !sourceData.isEmpty else { throw AccountPhotoProcessorError.emptyData }
            guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
                throw AccountPhotoProcessorError.invalidImage
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw AccountPhotoProcessorError.invalidImage
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { throw AccountPhotoProcessorError.invalidImage }
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: 0.82,
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw AccountPhotoProcessorError.invalidImage
            }
            let data = output as Data
            guard data.count <= Self.maximumEncodedBytes else {
                throw AccountPhotoProcessorError.outputTooLarge
            }
            return data
        }.value
    }
}
