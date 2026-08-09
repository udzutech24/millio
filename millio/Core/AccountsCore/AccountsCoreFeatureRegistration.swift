import Foundation
import SwiftData

/// Регистрация моделей ядра счетов (event-sourcing) в `ModelTypeRegistry` — закрывает релиз-блокер:
/// без неё CloudKit-бэкап/export/restore не переносили Account/AccountEvent/AccountGroup/
/// AccountDailySnapshot/HistoricalAssetPrice (progress/accounts-core-rebuild-handoff.md).
///
/// ВАЖНО: этот реестр — путь ТОЛЬКО для полного snapshot-бэкапа/restore на CloudKit.
/// Reconciliation (Track B, guest→user merge при логине) НЕ использует его для Account/AccountEvent/
/// AccountGroup/AccountDailySnapshot — `ScopeMergeReader.readGuestInput` явно исключает эти 4 типа
/// из `legacyData` (см. `ScopeMergeReader.newCoreTypeNames`), единственный merge-путь для них —
/// `ScopeMergeDedup.copyNewCore` (копия по id) либо пересборка снапшотов после merge (спека §0.4).
/// Если зарегистрировать их здесь БЕЗ этого исключения — reconciliation импортирует одни и те же
/// сущности дважды двумя независимыми путями с разной логикой реконструкции (например, `dayKey`
/// у `AccountEvent` — риск Т5).
/// HistoricalAssetPrice в это исключение НЕ входит: у него нет выделенного merge-пути в
/// `ScopeMergeDedup`, поэтому он мержится через общий импортёр как `HistoricalRate` (upsert по
/// symbol+dayKey) — как при полном бэкапе, так и при reconciliation.
struct AccountsCoreFeatureRegistration {
    static func register() {
        ModelTypeRegistry.shared.register(AccountGroup.self, typeName: "AccountGroup")
        ModelTypeRegistry.shared.register(Account.self, typeName: "Account")
        ModelTypeRegistry.shared.register(AccountEvent.self, typeName: "AccountEvent")
        ModelTypeRegistry.shared.register(AccountDailySnapshot.self, typeName: "AccountDailySnapshot")
        ModelTypeRegistry.shared.register(HistoricalAssetPrice.self, typeName: "HistoricalAssetPrice")
        ModelTypeRegistry.shared.register(
            HistoricalPortfolioValuation.self,
            typeName: "HistoricalPortfolioValuation"
        )
        ModelTypeRegistry.shared.registerBackupExporter(
            "HistoricalPortfolioValuation",
            exporter: HistoricalPortfolioValuationBackupExporter.export
        )

        ModelTypeRegistry.shared.registerImporter(AccountGroupImporter.self)
        ModelTypeRegistry.shared.registerImporter(AccountImporter.self)
        ModelTypeRegistry.shared.registerImporter(AccountEventImporter.self)
        ModelTypeRegistry.shared.registerImporter(AccountDailySnapshotImporter.self)
        ModelTypeRegistry.shared.registerImporter(HistoricalAssetPriceImporter.self)
        ModelTypeRegistry.shared.registerImporter(HistoricalPortfolioValuationImporter.self)
    }
}

// MARK: - AccountGroup Importer

struct AccountGroupImporter: ModelImporter {
    static func importType() -> String { "AccountGroup" }
    /// Импортируется первым в подграфе ядра — Account ссылается на группу по id.
    static var importPriority: Int { 30 }

    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let idString = data["id"] as? String, let id = UUID(uuidString: idString),
              let name = data["name"] as? String else {
            throw AppError.backupCorrupted
        }
        let colorHex = data["colorHex"] as? String
        let displayCurrency = data["displayCurrency"] as? String
        // Аддитивное поле (5c.7.6) — старый бэкап без него декодируется в nil, без краша.
        let customIconName = data["customIconName"] as? String
        let order = data["order"] as? Int ?? 0
        // Поля Фазы 1.5 (слияние с легаси-FinanceGroup) — с дефолтами для старых бэкапов без них.
        let isFavorite = data["isFavorite"] as? Bool ?? false
        let usesManualAccountOrdering = data["usesManualAccountOrdering"] as? Bool ?? false
        let priorityRaw = data["priorityRaw"] as? String ?? "normal"
        // Дефект 1 (ревью 2026-07-09): маркер идемпотентности ДОЛЖЕН пережить restore — без него
        // `GroupsMigrator` считал бы восстановленную группу немигрированной и перезаписывал бы поля
        // из легаси-FinanceGroup поверх правок пользователя, сделанных после миграции.
        let legacyFieldsMigratedAt = (data["legacyFieldsMigratedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))

        let descriptor = FetchDescriptor<AccountGroup>(predicate: #Predicate<AccountGroup> { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.name = name
            existing.colorHex = colorHex
            existing.displayCurrency = displayCurrency
            existing.customIconName = customIconName
            existing.order = order
            existing.isFavorite = isFavorite
            existing.usesManualAccountOrdering = usesManualAccountOrdering
            existing.priorityRaw = priorityRaw
            existing.legacyFieldsMigratedAt = legacyFieldsMigratedAt
            return
        }

        let group = AccountGroup(
            id: id, name: name, colorHex: colorHex, displayCurrency: displayCurrency, order: order,
            isFavorite: isFavorite, usesManualAccountOrdering: usesManualAccountOrdering, priorityRaw: priorityRaw
        )
        group.customIconName = customIconName
        group.legacyFieldsMigratedAt = legacyFieldsMigratedAt
        context.insert(group)
    }
}

// MARK: - Account Importer

struct AccountImporter: ModelImporter {
    static func importType() -> String { "Account" }
    /// После AccountGroup (30), до AccountEvent/AccountDailySnapshot (32) — те ссылаются на счёт по id.
    static var importPriority: Int { 31 }

    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let idString = data["id"] as? String, let id = UUID(uuidString: idString),
              let name = data["name"] as? String,
              let kindRaw = data["kindRaw"] as? String,
              let currency = data["currency"] as? String,
              let createdAtInterval = data["createdAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let createdAt = Date(timeIntervalSince1970: createdAtInterval)
        let includeInTotal = data["includeInTotal"] as? Bool ?? true
        let order = data["order"] as? Int ?? 0

        // Decode and validate the complete product/kind/meta tuple before mutating an existing
        // row. Old backups have no product columns and stay migration-compatible; once identity is
        // present, a contradictory tuple is rejected instead of silently becoming `.cash`.
        let cardMeta = (data["cardMeta"] as? [String: Any]).map(CardMeta.init(exportDict:))
        let depositMeta = (data["depositMeta"] as? [String: Any]).flatMap(DepositMeta.init(exportDict:))
        let loanMeta = (data["loanMeta"] as? [String: Any]).flatMap(LoanMeta.init(exportDict:))
        let debtMeta = (data["debtMeta"] as? [String: Any]).flatMap(DebtMeta.init(exportDict:))
        let marketMeta = (data["marketMeta"] as? [String: Any]).flatMap(MarketMeta.init(exportDict:))
        let manualAssetMeta = (data["manualAssetMeta"] as? [String: Any]).map(ManualAssetMeta.init(exportDict:))
        let productTypeRaw = data["productTypeRaw"] as? String
        let productMigrationReason = data["productMigrationReason"] as? String
        let valuationMembershipRevision = (data["valuationMembershipRevision"] as? NSNumber)?.int64Value
        let valuationFinancialRevision = (data["valuationFinancialRevision"] as? NSNumber)?.int64Value
        let valuationEventRevision = (data["valuationEventRevision"] as? NSNumber)?.int64Value

        if let productTypeRaw {
            guard let productType = AccountProductType(rawValue: productTypeRaw) else {
                throw AppError.backupCorrupted
            }
            do {
                try ProductDefinitionCatalog.validateStoredIdentity(
                    productType,
                    kindRaw: kindRaw,
                    metadata: AccountProductMetadata(
                        card: cardMeta,
                        deposit: depositMeta,
                        loan: loanMeta,
                        debt: debtMeta,
                        market: marketMeta,
                        manualAsset: manualAssetMeta
                    ),
                    migrationReason: productMigrationReason
                )
            } catch {
                throw AppError.backupCorrupted
            }
        } else if productMigrationReason != nil {
            throw AppError.backupCorrupted
        }

        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == id })
        let account: Account
        let isExisting: Bool
        if let existing = try? context.fetch(descriptor).first {
            account = existing
            isExisting = true
        } else {
            account = Account(
                id: id, name: name, kind: AccountKind(rawValue: kindRaw) ?? .cash,
                currency: currency, createdAt: createdAt, includeInTotal: includeInTotal, order: order
            )
            context.insert(account)
            isExisting = false
        }

        let preservesNewerProductTuple = isExisting
            && productTypeRaw == nil
            && account.productTypeRaw != nil

        account.name = name
        if !preservesNewerProductTuple {
            account.kindRaw = kindRaw
        }
        // An older backup must not erase a newer, already persisted identity during an upsert.
        // A genuinely new old-format row is classified below instead of remaining silent nil.
        if !preservesNewerProductTuple {
            account.productTypeRaw = productTypeRaw
            account.productMigrationReason = productMigrationReason
        }
        account.currency = currency
        account.createdAt = createdAt
        account.includeInTotal = includeInTotal
        account.order = order
        if let valuationMembershipRevision {
            account.valuationMembershipRevision = valuationMembershipRevision
        }
        if let valuationFinancialRevision {
            account.valuationFinancialRevision = valuationFinancialRevision
        }
        if let valuationEventRevision {
            account.valuationEventRevision = valuationEventRevision
        }
        account.note = data["note"] as? String
        account.archivedAt = (data["archivedAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        account.deletedAt = (data["deletedAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }

        if let groupIDString = data["groupID"] as? String, let groupID = UUID(uuidString: groupIDString) {
            let groupDescriptor = FetchDescriptor<AccountGroup>(predicate: #Predicate<AccountGroup> { $0.id == groupID })
            account.group = try? context.fetch(groupDescriptor).first
        } else {
            account.group = nil
        }

        if !preservesNewerProductTuple {
            account.cardMeta = cardMeta
            account.depositMeta = depositMeta
            account.loanMeta = loanMeta
            account.debtMeta = debtMeta
            account.marketMeta = marketMeta
            account.manualAssetMeta = manualAssetMeta
        }

        let hasValidStoredIdentity: Bool
        if let productType = account.productType {
            hasValidStoredIdentity = (try? ProductDefinitionCatalog.validateStoredIdentity(
                productType,
                kindRaw: account.kindRaw,
                metadata: AccountProductMetadata(account: account),
                migrationReason: account.productMigrationReason
            )) != nil
        } else {
            hasValidStoredIdentity = false
        }
        if !hasValidStoredIdentity {
            AccountProductIdentityMigrator.migrate(account)
        }
        var importedRevisionDimensions: Set<HistoricalValuationRevisionDimension> = []
        if account.valuationMembershipRevision == nil { importedRevisionDimensions.insert(.accountSet) }
        if account.valuationFinancialRevision == nil { importedRevisionDimensions.insert(.financial) }
        if account.valuationEventRevision == nil { importedRevisionDimensions.insert(.events) }
        HistoricalValuationRevisionTracker.bump(importedRevisionDimensions, on: account)
    }
}

// MARK: - AccountEvent Importer

struct AccountEventImporter: ModelImporter {
    static func importType() -> String { "AccountEvent" }
    static var importPriority: Int { 32 }

    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let idString = data["id"] as? String, let id = UUID(uuidString: idString),
              let dateInterval = data["date"] as? TimeInterval,
              let createdAtInterval = data["createdAt"] as? TimeInterval,
              let dayKey = data["dayKey"] as? String,
              let typeRaw = data["typeRaw"] as? String else {
            throw AppError.backupCorrupted
        }

        // Защитный дедуп по id (при обычном restore стор уже пуст — clearAllData отработал раньше).
        let descriptor = FetchDescriptor<AccountEvent>(predicate: #Predicate<AccountEvent> { $0.id == id })
        if (try? context.fetch(descriptor).first) != nil { return }

        var resolvedAccount: Account?
        if let accountIDString = data["accountID"] as? String, let accountID = UUID(uuidString: accountIDString) {
            let accDescriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == accountID })
            resolvedAccount = try? context.fetch(accDescriptor).first
        }

        let event = AccountEvent(
            id: id,
            account: resolvedAccount,
            date: Date(timeIntervalSince1970: dateInterval),
            createdAt: Date(timeIntervalSince1970: createdAtInterval),
            type: AccountEventType(rawValue: typeRaw) ?? .adjustment,
            amount: (data["amount"] as? String).flatMap { Decimal(string: $0) },
            quantity: (data["quantity"] as? String).flatMap { Decimal(string: $0) },
            unitPrice: (data["unitPrice"] as? String).flatMap { Decimal(string: $0) },
            fxRateToBase: (data["fxRateToBase"] as? String).flatMap { Decimal(string: $0) },
            fxProvisional: data["fxProvisional"] as? Bool ?? false,
            categoryID: data["categoryID"] as? String,
            note: data["note"] as? String,
            transferID: (data["transferID"] as? String).flatMap { UUID(uuidString: $0) },
            sourceTransactionID: data["sourceTransactionID"] as? String,
            originalAmount: (data["originalAmount"] as? String).flatMap { Decimal(string: $0) },
            originalCurrency: data["originalCurrency"] as? String,
            redenomRate: (data["redenomRate"] as? String).flatMap { Decimal(string: $0) },
            redenomFromCurrency: data["redenomFromCurrency"] as? String
        )
        // КРИТИЧНО (риск Т5): `AccountEvent.init` пересчитывает dayKey из date по ТЕКУЩЕЙ таймзоне —
        // восстанавливаем сохранённый в бэкапе dayKey, иначе смена TZ задним числом переносит
        // операцию в другой календарный день.
        event.dayKey = dayKey
        context.insert(event)
        // AccountImporter runs first and either restores the exact source counters or initializes
        // every missing legacy counter once. Per-event bumps here would turn N into N+eventCount
        // during restore, so an unchanged graph would no longer address its persisted close.
    }
}

// MARK: - AccountDailySnapshot Importer

struct AccountDailySnapshotImporter: ModelImporter {
    static func importType() -> String { "AccountDailySnapshot" }
    static var importPriority: Int { 32 }

    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let idString = data["id"] as? String, let id = UUID(uuidString: idString),
              let dayKey = data["dayKey"] as? String,
              let balanceString = data["balance"] as? String,
              let balance = Decimal(string: balanceString),
              let updatedAtInterval = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let descriptor = FetchDescriptor<AccountDailySnapshot>(predicate: #Predicate<AccountDailySnapshot> { $0.id == id })
        if (try? context.fetch(descriptor).first) != nil { return }

        var resolvedAccount: Account?
        if let accountIDString = data["accountID"] as? String, let accountID = UUID(uuidString: accountIDString) {
            let accDescriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == accountID })
            resolvedAccount = try? context.fetch(accDescriptor).first
        }

        let snapshot = AccountDailySnapshot(
            id: id,
            account: resolvedAccount,
            dayKey: dayKey,
            balance: balance,
            quantity: (data["quantity"] as? String).flatMap { Decimal(string: $0) },
            isClosed: data["isClosed"] as? Bool ?? false,
            updatedAt: Date(timeIntervalSince1970: updatedAtInterval)
        )
        context.insert(snapshot)
    }
}

// MARK: - HistoricalAssetPrice Importer

struct HistoricalAssetPriceImporter: ModelImporter {
    static func importType() -> String { "HistoricalAssetPrice" }
    // Независимый апенд-онли кэш, без зависимостей от Account/Group — importPriority по умолчанию (100).

    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let symbol = data["symbol"] as? String,
              let assetClassRaw = data["assetClassRaw"] as? String,
              let dayKey = data["dayKey"] as? String,
              let priceString = data["price"] as? String,
              let price = Decimal(string: priceString),
              let source = data["source"] as? String,
              let fetchedAtInterval = data["fetchedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        let fetchedAt = Date(timeIntervalSince1970: fetchedAtInterval)

        // Upsert по symbol+dayKey — тот же паттерн, что HistoricalRateImporter (append-only кэш,
        // мержится и при полном restore, и при reconciliation, где выделенного пути для него нет).
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { item in
                item.symbol == symbol && item.dayKey == dayKey
            }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.price = price
            existing.source = source
            existing.fetchedAt = fetchedAt
            return
        }

        let item = HistoricalAssetPrice(
            symbol: symbol,
            assetClass: MarketAssetClass(rawValue: assetClassRaw) ?? .stock,
            dayKey: dayKey,
            price: price,
            source: source,
            fetchedAt: fetchedAt
        )
        context.insert(item)
    }
}
