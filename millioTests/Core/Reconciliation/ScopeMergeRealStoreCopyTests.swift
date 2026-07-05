import Foundation
import SwiftData
import Testing
@testable import millio

/// B2d: интеграционный прогон merge на КОПИЯХ реальных сторов симулятора.
///
/// Не запускается в обычном CI: активируется только если задан env `MILLIO_MERGE_COPY_DIR`
/// (через `TEST_RUNNER_MILLIO_MERGE_COPY_DIR`), указывающий на папку с копиями
/// `millio_guest.store` и `millio_user.store`. Без него — зелёный no-op.
///
/// Оригиналы сторов НЕ трогаются — тест работает только с копиями (apply модифицирует копию user).
@Suite(.serialized)
@MainActor
struct ScopeMergeRealStoreCopyTests {

    private func registerFeatures() {
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        UserSubscriptionsFeatureRegistration.register()
    }

    private func makeContainer(url: URL, name: String) throws -> ModelContainer {
        try AppMigrationPlan.makeContainer(
            configuration: ModelConfiguration(name, url: url, cloudKitDatabase: .none)
        )
    }

    @Test func mergeOnRealStoreCopies() async throws {
        guard let dir = ProcessInfo.processInfo.environment["MILLIO_MERGE_COPY_DIR"], !dir.isEmpty else {
            return // не активировано — копий нет
        }
        let base = URL(fileURLWithPath: dir)
        let guestURL = base.appendingPathComponent("millio_guest.store")
        let userURL = base.appendingPathComponent("millio_user.store")
        guard FileManager.default.fileExists(atPath: guestURL.path),
              FileManager.default.fileExists(atPath: userURL.path) else {
            Issue.record("Копии не найдены в \(dir)")
            return
        }

        let state = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(state) }
        registerFeatures()

        let guestContainer = try makeContainer(url: guestURL, name: "millio_guest")
        let userContainer = try makeContainer(url: userURL, name: "millio_user_copy")

        // Опционально: удалить N транзакций из user-копии ДО merge — детерминированная демонстрация
        // переноса дельты на реальных данных (guest и user из одного исходного стора; после удаления
        // user отстаёт ровно на N, merge обязан восстановить их без дублей остальных ~200).
        var deletedN = 0
        if let raw = ProcessInfo.processInfo.environment["MILLIO_MERGE_DELETE_N"], let n = Int(raw), n > 0 {
            let ctx = ModelContext(userContainer)
            let txs = try ctx.fetch(FetchDescriptor<CashflowTransaction>())
            for tx in txs.prefix(n) { ctx.delete(tx) }
            try ctx.save()
            deletedN = min(n, txs.count)
        }

        let reader = ScopeGuestReader(modelContainer: guestContainer)
        let worker = ScopeMergeWorker(modelContainer: userContainer)

        let guestInput = try await reader.read()
        let userBefore = try await worker.snapshot()

        print("=== RECONCILIATION REAL-COPY RUN ===")
        print("BEFORE guest counts: \(guestInput.snapshot.modelCounts.sorted { $0.key < $1.key })")
        print("BEFORE user  counts: \(userBefore.modelCounts.sorted { $0.key < $1.key })")

        let targets = MultisetReconciler.targets(
            guestCounts: guestInput.snapshot.transactionCountsByFingerprint,
            userCounts: userBefore.transactionCountsByFingerprint
        )
        let result = try await worker.apply(input: guestInput, transactionTargets: targets)
        let userAfter = try await worker.snapshot()

        print("AFTER  user  counts: \(userAfter.modelCounts.sorted { $0.key < $1.key })")
        print("RESULT: +\(result.accountsAdded) счетов, +\(result.transactionsAdded) операций")

        // print() unit-теста не всплывает в xcodebuild-логе — дублируем сводку в файл для верификации с хоста.
        let summary = """
        guest      : \(guestInput.snapshot.modelCounts.sorted { $0.key < $1.key })
        userBefore : \(userBefore.modelCounts.sorted { $0.key < $1.key })
        userAfter  : \(userAfter.modelCounts.sorted { $0.key < $1.key })
        result     : +\(result.accountsAdded) accounts, +\(result.transactionsAdded) transactions
        """
        try? summary.write(to: base.appendingPathComponent("b2d-result.txt"), atomically: true, encoding: .utf8)

        // Инвариант sanity: слитый набор не превышает сумму сторон.
        for (model, after) in userAfter.modelCounts {
            let bound = (userBefore.modelCounts[model] ?? 0) + (guestInput.snapshot.modelCounts[model] ?? 0)
            #expect(after <= bound, "sanity нарушен для \(model): after=\(after) > bound=\(bound)")
        }

        // Транзакции: after >= max(before, guest) — дельта перенесена, база не потеряна.
        let txM = ScopeMergeReader.Model.transaction
        let txBefore = userBefore.modelCounts[txM] ?? 0
        let txGuest = guestInput.snapshot.modelCounts[txM] ?? 0
        let txAfter = userAfter.modelCounts[txM] ?? 0
        #expect(txAfter >= max(txBefore, txGuest), "транзакции потеряны: after=\(txAfter) < max(before=\(txBefore), guest=\(txGuest))")

        // Если предварительно удаляли N — они должны быть восстановлены merge'ем ровно (без дублей остальных).
        if deletedN > 0 {
            #expect(txAfter == txBefore + deletedN, "дельта восстановлена неверно: after=\(txAfter) != before(\(txBefore))+deleted(\(deletedN))")
            #expect(txAfter == txGuest, "после восстановления user должен сравняться с guest: after=\(txAfter) != guest=\(txGuest)")
        }

        // Идемпотентность: второй прогон на слитом user не меняет счётчики транзакций.
        let guestInput2 = try await reader.read()
        let userSnap2 = try await worker.snapshot()
        let targets2 = MultisetReconciler.targets(
            guestCounts: guestInput2.snapshot.transactionCountsByFingerprint,
            userCounts: userSnap2.transactionCountsByFingerprint
        )
        _ = try await worker.apply(input: guestInput2, transactionTargets: targets2)
        let userAfter2 = try await worker.snapshot()
        #expect(userAfter2.modelCounts[txM] == txAfter, "не идемпотентно: \(userAfter2.modelCounts[txM] ?? -1) != \(txAfter)")
        print("IDEMPOTENT re-run tx: \(userAfter2.modelCounts[txM] ?? -1) (== \(txAfter))")
    }
}
