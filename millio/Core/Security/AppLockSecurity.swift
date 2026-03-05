//
//  AppLockSecurity.swift
//  millio
//
//  Created by Александр Сидоркин on 21.02.2026.
//

import Foundation
import CryptoKit
import Security
import LocalAuthentication

protocol AppLockAuthContext: AnyObject {
    var biometryType: LABiometryType { get }
    var localizedCancelTitle: String? { get set }
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void)
}

extension LAContext: AppLockAuthContext {}

enum AppLockBiometricAuth {
    static var contextFactory: () -> AppLockAuthContext = { LAContext() }

    static func availableBiometry() -> LABiometryType {
        let context = contextFactory()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    static func canUseBiometrics() -> Bool {
        let context = contextFactory()
        return preferredUnlockPolicy(for: context) != nil
    }

    static func buttonTitle() -> String {
        switch availableBiometry() {
        case .faceID:
            return "Unlock with Face ID"
        case .touchID:
            return "Unlock with Touch ID"
        default:
            return "Unlock with biometrics"
        }
    }

    static func settingsTitle() -> String {
        switch availableBiometry() {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometrics"
        }
    }

    static func settingsIconSystemName() -> String {
        switch availableBiometry() {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        default:
            return "person.crop.circle.badge.checkmark"
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let context = contextFactory()
        guard let policy = preferredUnlockPolicy(for: context) else { return false }

        return await withCheckedContinuation { continuation in
            context.localizedCancelTitle = "Cancel"
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Разрешаем fallback на системный passcode только когда биометрия
    /// временно заблокирована (`biometryLockout`), чтобы пользователь
    /// мог восстановить Face ID/Touch ID без dead-end состояния.
    static func preferredUnlockPolicy(for context: AppLockAuthContext) -> LAPolicy? {
        var biometricError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError) {
            return .deviceOwnerAuthenticationWithBiometrics
        }
        guard let laError = biometricError as? LAError, laError.code == .biometryLockout else {
            return nil
        }
        var deviceAuthError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &deviceAuthError) {
            return .deviceOwnerAuthentication
        }
        return nil
    }
}

final class AppLockPinStore {
    static let shared = AppLockPinStore(service: "com.millio.app-lock", account: "pin_payload_v1")

    private let service: String
    private let account: String
    private let accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func hasPin() -> Bool {
        payload() != nil
    }

    func save(pin: String) throws {
        let normalized = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(pin: normalized) else {
            throw AppLockFailureCode.invalidPinFormat.appError
        }

        let salt = try randomBytes(count: 16)
        let hash = Data(SHA256.hash(data: Data(normalized.utf8) + salt))
        let value = salt + hash
        try set(value)
    }

    func verify(pin: String) -> Bool {
        let normalized = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(pin: normalized), let payload = payload(), payload.count == 48 else {
            return false
        }

        let salt = payload.prefix(16)
        let expectedHash = payload.suffix(32)
        let candidate = Data(SHA256.hash(data: Data(normalized.utf8) + salt))
        return Data(expectedHash) == candidate
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func isValid(pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy(\.isNumber)
    }

    private func payload() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func set(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw AppLockFailureCode.keychainPinUpdateFailed.appError
            }
            return
        }

        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = accessible
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppLockFailureCode.keychainPinSaveFailed.appError
        }
    }

    private func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw AppLockFailureCode.secureRandomPinGenerationFailed.appError
        }
        return data
    }
}
