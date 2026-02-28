//
//  ProfileAvatarStorage.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import UIKit

/// Сохранение аватарки профиля в Application Support и обновление пути в SettingsManager.
enum ProfileAvatarStorage {
    private static let avatarFileName = "avatar.jpg"
    
    /// Сохраняет изображение на диск и записывает путь в SettingsManager.
    /// - Parameter imageData: данные изображения (например, из PhotosPicker).
    /// - Returns: путь к сохранённому файлу или nil при ошибке.
    @discardableResult
    static func saveAvatar(imageData: Data) -> String? {
        guard let fileURL = profileAvatarFileURL() else { return nil }
        let fileManager = FileManager.default
        
        do {
            let dirURL = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dirURL.path) {
                try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            let dataToWrite: Data
            if let image = UIImage(data: imageData),
               let jpeg = image.jpegData(compressionQuality: 0.85) {
                dataToWrite = jpeg
            } else {
                dataToWrite = imageData
            }
            try dataToWrite.write(to: fileURL)
            let path = fileURL.path
            SettingsManager.shared.profileAvatarFilePath = path
            return path
        } catch {
            return nil
        }
    }
    
    /// URL файла аватарки в Application Support/Profile.
    static func profileAvatarFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Profile").appendingPathComponent(avatarFileName)
    }
}
