import Foundation
import SwiftData
import Testing
@testable import millio

/// B2b: SwiftData-мержер guest→user на двух in-memory сторах.
/// Кейсы спеки §5: guest==user / guest⊃user / пустой guest / LWW / идемпотентный ретрай / new-core.
@Suite(.serialized)
@MainActor
struct ScopeMergeWorkerTests {

    // MARK: - Инфраструктура

    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: AppSchema.create(), configurations: [config])
    }

    private func registerFeatures() {
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        UserSubscriptionsFeatureRegistration.register()
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let fixedCreated = Date(timeIntervalSince1970: 1_600_000_000)

    /// Транзакция с фиксированным fingerprint (type|date|amount|createdAt).
    @discardableResult
    private func insertTx(_ container: ModelContainer, amount: Double, note: String, updatedAt: TimeInterval) -> CashflowTransaction {
        let tx = CashflowTransaction(transactionType: .expense, amount: amount, currency: "RUB",
                                     transactionDate: fixedDate, note: note)
        tx.createdAt = fixedCreated
        tx.updatedAt = Date(timeIntervalSince1970: updatedAt)
        container.mainContext.insert(tx)
        return tx
    }

    private func insertCoreAccount(_ container: ModelContainer, id: UUID, name: String) {
        let account = Account(id: id, name: name, kind: .manualAsset, currency: "RUB")
        let event = AccountEvent(id: UUID(), account: account, date: fixedDate,
                                 type: .openingBalance, amount: 1000)
        container.mainContext.insert(account)
        container.mainContext.insert(event)
    }

    private func save(_ container: ModelContainer) { try? container.mainContext.save() }

    private func count<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) -> Int {
        (try? ModelContext(container).fetchCount(FetchDescriptor<T>())) ?? -1
    }

    /// Выполняет полный merge guest→user (reader → targets → worker.apply). Возвращает результат.
    private func runMerge(guest: ModelContainer, user: ModelContainer) async throws -> ScopeMergeWorkerResult {
        let reader = ScopeGuestReader(modelContainer: guest)
        let input = try await reader.read()
        let worker = ScopeMergeWorker(modelContainer: user)
        let userSnap = try await worker.snapshot()
        let targets = MultisetReconciler.targets(
            guestCounts: input.snapshot.transactionCountsByFingerprint,
            userCounts: userSnap.transactionCountsByFingerprint
        )
        return try await worker.apply(input: input, transactionTargets: targets)
    }

    private func withRegistry(_ body: () async throws -> Void) async throws {
        let state = ModelTypeRegistry.shared.captureState()
        registerFeatures()
        do { try await body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    // MARK: - Кейсы

    @Test func guestEqualsUser_noDuplicates() async throws {
        try await withRegistry {
            let guest = makeContainer(); let user = makeContainer()
            insertTx(guest, amount: 100, note: "base", updatedAt: 100); save(guest)
            insertTx(user, amount: 100, note: "base", updatedAt: 100); save(user)

            let result = try await runMerge(guest: guest, user: user)
            #expect(count(CashflowTransaction.self, in: user) == 1) // общая база не задвоилась
            #expect(result.transactionsAdded == 0)
        }
    }

    @Test func guestSupersetOfUser_transfersDeltaOnly() async throws {
        try await withRegistry {
            let guest = makeContainer(); let user = makeContainer()
            // Общая база + дельта в guest.
            insertTx(guest, amount: 100, note: "base", updatedAt: 100)
            insertTx(guest, amount: 250, note: "delta", updatedAt: 150); save(guest)
            insertTx(user, amount: 100, note: "base", updatedAt: 100); save(user)

            let result = try await runMerge(guest: guest, user: user)
            #expect(count(CashflowTransaction.self, in: user) == 2) // base + delta, без дубля базы
            #expect(result.transactionsAdded == 1)
        }
    }

    @Test func emptyGuest_isNoOp() async throws {
        try await withRegistry {
            let guest = makeContainer(); let user = makeContainer()
            insertTx(user, amount: 100, note: "u", updatedAt: 100); save(user)

            let result = try await runMerge(guest: guest, user: user)
            #expect(count(CashflowTransaction.self, in: user) == 1)
            #expect(result.transactionsAdded == 0)
            #expect(result.accountsAdded == 0)
        }
    }

    @Test func mutualEdit_lastWriteWinsByUpdatedAt() async throws {
        try await withRegistry {
            let guest = makeContainer(); let user = makeContainer()
            // Один и тот же fingerprint, но разный note и updatedAt: guest новее.
            insertTx(guest, amount: 100, note: "guest-edit", updatedAt: 200); save(guest)
            insertTx(user, amount: 100, note: "user-old", updatedAt: 100); save(user)

            _ = try await runMerge(guest: guest, user: user)
            #expect(count(CashflowTransaction.self, in: user) == 1)
            let survivorNote = try ModelContext(user).fetch(FetchDescriptor<CashflowTransaction>()).first?.note
            #expect(survivorNote == "guest-edit") // LWW: выжил более свежий guest
        }
    }

    @Test func idempotentRetry_secondRunStable() async throws {
        try await withRegistry {
            let guest = makeContainer(); let user = makeContainer()
            insertTx(guest, amount: 100, note: "base", updatedAt: 100)
            insertTx(guest, amount: 250, note: "delta", updatedAt: 150); save(guest)
            insertTx(user, amount: 100, note: "base", updatedAt: 100); save(user)

            _ = try await runMerge(guest: guest, user: user)
            let afterFirst = count(CashflowTransaction.self, in: user)
            _ = try await runMerge(guest: guest, user: user) // повтор с полным guest
            let afterSecond = count(CashflowTransaction.self, in: user)
            #expect(afterFirst == 2)
            #expect(afterSecond == 2) // счётчик стабилен — идемпотентно
        }
    }

    @Test func newCore_groupNameFallback_reCeptsAccountsWithoutDuplicateGroup() async throws {
        try await withRegistry {
            let guest = makeContainer(); let user = makeContainer()
            // Одноимённая группа «Карты» в обоих сторах, но с РАЗНЫМИ id.
            let userGroup = AccountGroup(id: UUID(), name: "Карты")
            user.mainContext.insert(userGroup); save(user)

            let guestGroup = AccountGroup(id: UUID(), name: "Карты")
            let guestAccount = Account(id: UUID(), name: "Дебетовая", kind: .debitCard, currency: "RUB")
            guestAccount.group = guestGroup
            guest.mainContext.insert(guestGroup)
            guest.mainContext.insert(guestAccount); save(guest)

            _ = try await runMerge(guest: guest, user: user)
            // Митигация B1b №4: без дубля группы — счёт перецеплен к существующей user-группе.
            #expect(count(AccountGroup.self, in: user) == 1)
            #expect(count(Account.self, in: user) == 1)
            let acc = try ModelContext(user).fetch(FetchDescriptor<Account>()).first
            #expect(acc?.group?.name == "Карты")
        }
    }

    @Test func newCore_copiedByIdAndIdempotent() async throws {
        try await withRegistry {
            let guest = makeContainer(); let user = makeContainer()
            let accID = UUID()
            insertCoreAccount(guest, id: accID, name: "Core"); save(guest)
            // user без new-core

            let result = try await runMerge(guest: guest, user: user)
            #expect(count(Account.self, in: user) == 1)
            #expect(count(AccountEvent.self, in: user) == 1)
            #expect(result.accountsAdded == 1)
            #expect(result.transactionsAdded == 1) // core-event учитывается как операция

            _ = try await runMerge(guest: guest, user: user) // повтор по тому же id
            #expect(count(Account.self, in: user) == 1) // без дубля
            #expect(count(AccountEvent.self, in: user) == 1)
        }
    }
}
