import Foundation

enum ProfileDisplayNameResolver {
    static func headerDisplayName(storedDisplayName: String, authUser: AuthUser?) -> String {
        let normalizedStored = storedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedStored.isEmpty, !SettingsManager.isDefaultProfileDisplayName(normalizedStored) {
            return normalizedStored
        }

        if let authName = userDisplayName(authUser) {
            return authName
        }

        return SettingsManager.defaultProfileDisplayName
    }

    static func userDisplayName(_ authUser: AuthUser?) -> String? {
        authUser?.preferredDisplayName
    }
}

private extension AuthUser {
    var preferredDisplayName: String? {
        let normalizedFullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedFullName, !normalizedFullName.isEmpty {
            return normalizedFullName
        }

        let nameParts = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !nameParts.isEmpty {
            return nameParts.joined(separator: " ")
        }

        return nil
    }
}
