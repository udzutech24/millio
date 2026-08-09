import Foundation
import SwiftData

enum RealEstatePropertyType: String, Codable, CaseIterable, Identifiable {
    case apartment
    case house
    case land
    case commercial
    case other

    var id: String { rawValue }

    /// Static keys are intentional: dynamic String Catalog keys are not extracted reliably and
    /// previously leaked `real_estate.type.*` into the picker and detail screen.
    var localizedTitle: String {
        switch self {
        case .apartment: L("real_estate.type.apartment")
        case .house: L("real_estate.type.house")
        case .land: L("real_estate.type.land")
        case .commercial: L("real_estate.type.commercial")
        case .other: L("real_estate.type.other")
        }
    }

    var systemImage: String {
        switch self {
        case .apartment: "building.2.fill"
        case .house: "house.fill"
        case .land: "leaf.fill"
        case .commercial: "building.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

enum RealEstateReminder: Int, CaseIterable, Identifiable {
    case off = 0
    case threeMonths = 3
    case sixMonths = 6
    case twelveMonths = 12
    case twentyFourMonths = 24

    var id: Int { rawValue }
    var persistedMonths: Int? { self == .off ? nil : rawValue }

    init(persistedMonths: Int?) {
        self = Self(rawValue: persistedMonths ?? 0) ?? .off
    }

    var localizedTitle: String {
        switch self {
        case .off: L("real_estate.reminder.never")
        case .threeMonths: L("real_estate.reminder.3")
        case .sixMonths: L("real_estate.reminder.6")
        case .twelveMonths: L("real_estate.reminder.12")
        case .twentyFourMonths: L("real_estate.reminder.24")
        }
    }
}

struct RealEstatePhotoDraft: Identifiable, Equatable {
    let id: UUID
    var data: Data
    var isCover: Bool

    init(id: UUID = UUID(), data: Data, isCover: Bool = false) {
        self.id = id
        self.data = data
        self.isCover = isCover
    }
}

enum RealEstateEditPolicy {
    static func isReadOnly(archivedAt: Date?, deletedAt: Date?) -> Bool {
        archivedAt != nil || deletedAt != nil
    }

    static func eligibleMortgage(_ loan: Account, for property: Account) -> Bool {
        loan.kind == .loan && loan.currency == property.currency && loan.archivedAt == nil && loan.deletedAt == nil
    }
}

/// Product-specific metadata lives outside `Account` so V8 is an additive migration and the
/// already shipped V7 Account checksum remains immutable.
@Model
final class RealEstateProfile: Persistable {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var propertyTypeRaw: String = RealEstatePropertyType.other.rawValue

    var propertyType: RealEstatePropertyType {
        get { RealEstatePropertyType(rawValue: propertyTypeRaw) ?? .other }
        set { propertyTypeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), accountID: UUID, propertyType: RealEstatePropertyType) {
        self.id = id
        self.accountID = accountID
        self.propertyTypeRaw = propertyType.rawValue
    }

    func export() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "RealEstateProfile",
            "id": id.uuidString,
            "accountID": accountID.uuidString,
            "propertyTypeRaw": propertyTypeRaw,
        ])
    }

    static func `import`(_ data: Data) throws {}
}

enum AccountAttachmentKind: String, Codable {
    case photo
}

@Model
final class AccountAttachment: Persistable {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var kindRaw: String = AccountAttachmentKind.photo.rawValue
    var order: Int = 0
    var isCover: Bool = false
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var mediaData: Data = Data()

    var kind: AccountAttachmentKind {
        get { AccountAttachmentKind(rawValue: kindRaw) ?? .photo }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        accountID: UUID,
        kind: AccountAttachmentKind = .photo,
        order: Int,
        isCover: Bool,
        createdAt: Date = Date(),
        mediaData: Data
    ) {
        self.id = id
        self.accountID = accountID
        self.kindRaw = kind.rawValue
        self.order = order
        self.isCover = isCover
        self.createdAt = createdAt
        self.mediaData = mediaData
    }

    func export() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "AccountAttachment",
            "id": id.uuidString,
            "accountID": accountID.uuidString,
            "kindRaw": kindRaw,
            "order": order,
            "isCover": isCover,
            "createdAt": createdAt.timeIntervalSince1970,
            "mediaData": mediaData.base64EncodedString(),
        ])
    }

    static func `import`(_ data: Data) throws {}
}
