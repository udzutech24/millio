//
//  DataScope.swift
//  millio
//
//  Created by Codex on 15.03.2026.
//

import Foundation
import CryptoKit

enum DataScope: Equatable, Sendable {
    case guest
    case user(id: String)

    var diagnosticKind: String {
        switch self {
        case .guest: "guest"
        case .user: "authenticated"
        }
    }

    var storeConfigurationName: String {
        switch self {
        case .guest:
            return "millio_guest"
        case .user(let id):
            return "millio_user_\(Self.hash(id))"
        }
    }

    var storeFileName: String {
        "\(storeConfigurationName).store"
    }

    static func current(isAuthenticated: Bool, user: AuthUser?) -> DataScope {
        guard
            isAuthenticated,
            let rawUserID = user?.id.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawUserID.isEmpty
        else {
            return .guest
        }
        return .user(id: rawUserID)
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
