import Foundation
import SwiftData

enum AssetCatalogItemType: String, Codable, CaseIterable, Sendable {
    case stock
    case crypto
    case etf
    case bond
    case metal
    case other
}

enum AssetProviderMappingStatus: String, Codable, CaseIterable, Sendable {
    case active
    case inactive
    case deprecated
}

@Model
final class AssetCatalogItem: Persistable {
    /// Stable internal identity used by holdings and watchlists.
    var assetID: String = ""
    var canonicalSymbol: String = ""
    var displayName: String = ""
    var assetTypeRaw: String = AssetCatalogItemType.other.rawValue
    var currency: String?
    var country: String?
    var isin: String?
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        assetID: String,
        canonicalSymbol: String,
        displayName: String,
        assetType: AssetCatalogItemType,
        currency: String?,
        country: String?,
        isin: String? = nil,
        isActive: Bool = true
    ) {
        self.assetID = assetID
        self.canonicalSymbol = canonicalSymbol
        self.displayName = displayName
        self.assetTypeRaw = assetType.rawValue
        self.currency = currency
        self.country = country
        self.isin = isin
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var assetType: AssetCatalogItemType {
        get { AssetCatalogItemType(rawValue: assetTypeRaw) ?? .other }
        set { assetTypeRaw = newValue.rawValue }
    }

    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "AssetCatalogItem",
            "assetID": assetID,
            "canonicalSymbol": canonicalSymbol,
            "displayName": displayName,
            "assetTypeRaw": assetTypeRaw,
            "isActive": isActive,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]

        if let currency {
            dict["currency"] = currency
        }
        if let country {
            dict["country"] = country
        }
        if let isin {
            dict["isin"] = isin
        }

        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["assetID"] as? String != nil,
              dict["canonicalSymbol"] as? String != nil,
              dict["displayName"] as? String != nil else {
            throw AppError.backupCorrupted
        }
    }

    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "AssetCatalogItem" &&
        dict["assetID"] as? String != nil &&
        dict["canonicalSymbol"] as? String != nil
    }
}

@Model
final class AssetProviderMapping: Persistable {
    var mappingID: String = ""
    var assetID: String = ""
    var providerName: String = ""
    var providerSymbol: String?
    var providerExchangeCode: String?
    var providerInstrumentID: String?
    var statusRaw: String = AssetProviderMappingStatus.active.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastVerifiedAt: Date?

    init(
        mappingID: String,
        assetID: String,
        providerName: String,
        providerSymbol: String?,
        providerExchangeCode: String?,
        providerInstrumentID: String?,
        status: AssetProviderMappingStatus,
        lastVerifiedAt: Date? = nil
    ) {
        self.mappingID = mappingID
        self.assetID = assetID
        self.providerName = providerName
        self.providerSymbol = providerSymbol
        self.providerExchangeCode = providerExchangeCode
        self.providerInstrumentID = providerInstrumentID
        self.statusRaw = status.rawValue
        self.lastVerifiedAt = lastVerifiedAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var status: AssetProviderMappingStatus {
        get { AssetProviderMappingStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "AssetProviderMapping",
            "mappingID": mappingID,
            "assetID": assetID,
            "providerName": providerName,
            "statusRaw": statusRaw,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]

        if let providerSymbol {
            dict["providerSymbol"] = providerSymbol
        }
        if let providerExchangeCode {
            dict["providerExchangeCode"] = providerExchangeCode
        }
        if let providerInstrumentID {
            dict["providerInstrumentID"] = providerInstrumentID
        }
        if let lastVerifiedAt {
            dict["lastVerifiedAt"] = lastVerifiedAt.timeIntervalSince1970
        }

        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["mappingID"] as? String != nil,
              dict["assetID"] as? String != nil,
              dict["providerName"] as? String != nil else {
            throw AppError.backupCorrupted
        }
    }

    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "AssetProviderMapping" &&
        dict["mappingID"] as? String != nil &&
        dict["assetID"] as? String != nil
    }
}

struct ResolvedAssetIdentity: Sendable, Equatable {
    let assetID: String
    let canonicalSymbol: String
    let providerName: String
    let providerSymbol: String?
    let providerExchangeCode: String?
    let providerInstrumentID: String?
    let displayName: String
    let assetType: AssetCatalogItemType
    let currency: String?
    let country: String?
    let status: AssetProviderMappingStatus
}

enum MarketAssetIdentityResolver {
    static let defaultProviderName = "market-backend"

    static func resolve(
        category: InvestmentCategory,
        symbol: String?,
        exchange: String?,
        instrumentName: String?,
        micCode: String?,
        instrumentType: String?,
        currency: String?,
        country: String?,
        providerName: String? = nil
    ) -> ResolvedAssetIdentity? {
        let normalizedSymbol = symbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedSymbol, !normalizedSymbol.isEmpty else {
            return nil
        }

        let canonicalSymbol = canonicalAssetSymbol(
            symbol: normalizedSymbol,
            exchange: exchange
        )

        let assetType = assetType(for: category, instrumentType: instrumentType)
        let assetID = makeAssetID(category: category, canonicalSymbol: canonicalSymbol)
        let provider = normalizedProviderName(providerName)
        let trimmedInstrumentName = instrumentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = trimmedInstrumentName.isEmpty
            ? normalizedSymbol.uppercased()
            : trimmedInstrumentName

        return ResolvedAssetIdentity(
            assetID: assetID,
            canonicalSymbol: canonicalSymbol,
            providerName: provider,
            providerSymbol: normalizedSymbol.uppercased(),
            providerExchangeCode: normalizedExchangeCode(exchange, micCode: micCode),
            providerInstrumentID: nil,
            displayName: displayName,
            assetType: assetType,
            currency: currency?.uppercased(),
            country: country,
            status: .active
        )
    }

    private static func canonicalAssetSymbol(symbol: String, exchange: String?) -> String {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteLookupKey = MarketInstrumentIdentity.canonicalQuoteLookupKey(
            symbol: trimmedSymbol,
            exchange: exchange
        )
        let baseTicker = StockBulkImportCandidate.canonicalTicker(from: trimmedSymbol)

        guard !baseTicker.isEmpty else {
            return quoteLookupKey.isEmpty ? trimmedSymbol.uppercased() : quoteLookupKey.uppercased()
        }

        switch normalizedAssetMarket(exchange: exchange, symbol: trimmedSymbol) {
        case nil, "US", "NASDAQ", "NYSE", "AMEX", "BATS", "IEX":
            return baseTicker
        case let market?:
            return "\(market):\(baseTicker)"
        }
    }

    private static func normalizedProviderName(_ providerName: String?) -> String {
        let trimmed = providerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed! : defaultProviderName).lowercased()
    }

    private static func normalizedAssetMarket(exchange: String?, symbol: String) -> String? {
        let normalizedExchange = exchange?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let normalizedExchange, !normalizedExchange.isEmpty {
            return normalizedExchange
        }

        let rawSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if rawSymbol.contains(":"),
           let market = rawSymbol.split(separator: ":", maxSplits: 1).first {
            let normalizedMarket = String(market).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return normalizedMarket.isEmpty ? nil : normalizedMarket
        }

        if rawSymbol.hasSuffix(".US") {
            return "US"
        }

        return nil
    }

    private static func normalizedExchangeCode(_ exchange: String?, micCode: String?) -> String? {
        let normalizedExchange = exchange?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let normalizedExchange, !normalizedExchange.isEmpty {
            return normalizedExchange
        }

        let normalizedMIC = micCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalizedMIC?.isEmpty == false ? normalizedMIC : nil
    }

    private static func assetType(
        for category: InvestmentCategory,
        instrumentType: String?
    ) -> AssetCatalogItemType {
        let normalizedInstrumentType = instrumentType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalizedInstrumentType.contains("etf") {
            return .etf
        }
        if normalizedInstrumentType.contains("bond") || category == .bonds {
            return .bond
        }
        if normalizedInstrumentType.contains("metal") || category == .metals {
            return .metal
        }

        switch category {
        case .stocks:
            return .stock
        case .crypto:
            return .crypto
        default:
            return .other
        }
    }

    private static func makeAssetID(category: InvestmentCategory, canonicalSymbol: String) -> String {
        let categoryKey = category.rawValue.lowercased()
        let symbolKey = canonicalSymbol
            .lowercased()
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        return "asset.\(categoryKey).\(symbolKey)"
    }
}

@MainActor
struct AssetCatalogStore {
    let modelContext: ModelContext

    @discardableResult
    func sync(identity: ResolvedAssetIdentity) -> Bool {
        let didUpdateCatalog = upsertCatalogItem(identity)
        let didUpdateMapping = upsertProviderMapping(identity)
        return didUpdateCatalog || didUpdateMapping
    }

    @discardableResult
    private func upsertCatalogItem(_ identity: ResolvedAssetIdentity) -> Bool {
        let assetID = identity.assetID
        let descriptor = FetchDescriptor<AssetCatalogItem>(
            predicate: #Predicate<AssetCatalogItem> { item in
                item.assetID == assetID
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            let didChange =
                existing.canonicalSymbol != identity.canonicalSymbol ||
                existing.displayName != identity.displayName ||
                existing.assetType != identity.assetType ||
                existing.currency != identity.currency ||
                existing.country != identity.country ||
                existing.isActive != (identity.status == .active)

            guard didChange else { return false }
            existing.canonicalSymbol = identity.canonicalSymbol
            existing.displayName = identity.displayName
            existing.assetType = identity.assetType
            existing.currency = identity.currency
            existing.country = identity.country
            existing.isActive = identity.status == .active
            existing.updatedAt = Date()
            return true
        }

        let item = AssetCatalogItem(
            assetID: identity.assetID,
            canonicalSymbol: identity.canonicalSymbol,
            displayName: identity.displayName,
            assetType: identity.assetType,
            currency: identity.currency,
            country: identity.country,
            isActive: identity.status == .active
        )
        modelContext.insert(item)
        return true
    }

    @discardableResult
    private func upsertProviderMapping(_ identity: ResolvedAssetIdentity) -> Bool {
        let mappingID = makeMappingID(
            assetID: identity.assetID,
            providerName: identity.providerName,
            providerSymbol: identity.providerSymbol,
            providerExchangeCode: identity.providerExchangeCode
        )

        let descriptor = FetchDescriptor<AssetProviderMapping>(
            predicate: #Predicate<AssetProviderMapping> { mapping in
                mapping.mappingID == mappingID
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            let didChange =
                existing.assetID != identity.assetID ||
                existing.providerSymbol != identity.providerSymbol ||
                existing.providerExchangeCode != identity.providerExchangeCode ||
                existing.providerInstrumentID != identity.providerInstrumentID ||
                existing.status != identity.status

            guard didChange else { return false }
            existing.assetID = identity.assetID
            existing.providerSymbol = identity.providerSymbol
            existing.providerExchangeCode = identity.providerExchangeCode
            existing.providerInstrumentID = identity.providerInstrumentID
            existing.status = identity.status
            existing.updatedAt = Date()
            existing.lastVerifiedAt = Date()
            return true
        }

        let mapping = AssetProviderMapping(
            mappingID: mappingID,
            assetID: identity.assetID,
            providerName: identity.providerName,
            providerSymbol: identity.providerSymbol,
            providerExchangeCode: identity.providerExchangeCode,
            providerInstrumentID: identity.providerInstrumentID,
            status: identity.status,
            lastVerifiedAt: Date()
        )
        modelContext.insert(mapping)
        return true
    }

    private func makeMappingID(
        assetID: String,
        providerName: String,
        providerSymbol: String?,
        providerExchangeCode: String?
    ) -> String {
        let symbolKey = providerSymbol?.lowercased() ?? "none"
        let exchangeKey = providerExchangeCode?.lowercased() ?? "none"
        return "\(assetID)|\(providerName.lowercased())|\(symbolKey)|\(exchangeKey)"
    }

    @discardableResult
    func syncIfSupported(identity: ResolvedAssetIdentity) -> Bool {
        guard supportsCatalogModels() else { return false }
        return sync(identity: identity)
    }

    @discardableResult
    func migrateInvestmentIfNeeded(_ investment: Investment) -> Bool {
        let resolvedIdentity = MarketAssetIdentityResolver.resolve(
            category: investment.category,
            symbol: investment.marketSymbol,
            exchange: investment.marketExchange,
            instrumentName: investment.name,
            micCode: investment.marketMICCode,
            instrumentType: inferredInstrumentType(for: investment),
            currency: investment.marketCurrency ?? investment.currency,
            country: nil,
            providerName: investment.marketProviderRaw
        )

        guard let resolvedIdentity else { return false }

        var didChange = false
        if investment.assetID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            investment.assetID = resolvedIdentity.assetID
            investment.updatedAt = Date()
            didChange = true
        }

        let didSync = syncIfSupported(identity: resolvedIdentity)
        return didChange || didSync
    }

    private func supportsCatalogModels() -> Bool {
        let schema = modelContext.container.schema
        return schema.entity(for: AssetCatalogItem.self) != nil &&
            schema.entity(for: AssetProviderMapping.self) != nil
    }

    private func inferredInstrumentType(for investment: Investment) -> String? {
        switch investment.category {
        case .crypto:
            return "Cryptocurrency"
        case .bonds:
            return "Bond"
        case .metals:
            return "Metal"
        case .stocks:
            return "Common Stock"
        default:
            return nil
        }
    }
}

struct AssetCatalogItemImporter: ModelImporter {
    static func importType() -> String { "AssetCatalogItem" }

    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let assetID = dict["assetID"] as? String,
              let canonicalSymbol = dict["canonicalSymbol"] as? String,
              let displayName = dict["displayName"] as? String,
              let assetTypeRaw = dict["assetTypeRaw"] as? String,
              let createdAt = dict["createdAt"] as? TimeInterval,
              let updatedAt = dict["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let descriptor = FetchDescriptor<AssetCatalogItem>(
            predicate: #Predicate<AssetCatalogItem> { item in
                item.assetID == assetID
            }
        )

        let target = (try? context.fetch(descriptor).first) ?? {
            let item = AssetCatalogItem(
                assetID: assetID,
                canonicalSymbol: canonicalSymbol,
                displayName: displayName,
                assetType: AssetCatalogItemType(rawValue: assetTypeRaw) ?? .other,
                currency: dict["currency"] as? String,
                country: dict["country"] as? String,
                isin: dict["isin"] as? String,
                isActive: dict["isActive"] as? Bool ?? true
            )
            context.insert(item)
            return item
        }()

        target.canonicalSymbol = canonicalSymbol
        target.displayName = displayName
        target.assetTypeRaw = assetTypeRaw
        target.currency = dict["currency"] as? String
        target.country = dict["country"] as? String
        target.isin = dict["isin"] as? String
        target.isActive = dict["isActive"] as? Bool ?? true
        target.createdAt = Date(timeIntervalSince1970: createdAt)
        target.updatedAt = Date(timeIntervalSince1970: updatedAt)
    }
}

struct AssetProviderMappingImporter: ModelImporter {
    static func importType() -> String { "AssetProviderMapping" }

    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let mappingID = dict["mappingID"] as? String,
              let assetID = dict["assetID"] as? String,
              let providerName = dict["providerName"] as? String,
              let statusRaw = dict["statusRaw"] as? String,
              let createdAt = dict["createdAt"] as? TimeInterval,
              let updatedAt = dict["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let descriptor = FetchDescriptor<AssetProviderMapping>(
            predicate: #Predicate<AssetProviderMapping> { mapping in
                mapping.mappingID == mappingID
            }
        )

        let target = (try? context.fetch(descriptor).first) ?? {
            let mapping = AssetProviderMapping(
                mappingID: mappingID,
                assetID: assetID,
                providerName: providerName,
                providerSymbol: dict["providerSymbol"] as? String,
                providerExchangeCode: dict["providerExchangeCode"] as? String,
                providerInstrumentID: dict["providerInstrumentID"] as? String,
                status: AssetProviderMappingStatus(rawValue: statusRaw) ?? .active,
                lastVerifiedAt: (dict["lastVerifiedAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
            )
            context.insert(mapping)
            return mapping
        }()

        target.assetID = assetID
        target.providerName = providerName
        target.providerSymbol = dict["providerSymbol"] as? String
        target.providerExchangeCode = dict["providerExchangeCode"] as? String
        target.providerInstrumentID = dict["providerInstrumentID"] as? String
        target.statusRaw = statusRaw
        target.lastVerifiedAt = (dict["lastVerifiedAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        target.createdAt = Date(timeIntervalSince1970: createdAt)
        target.updatedAt = Date(timeIntervalSince1970: updatedAt)
    }
}
