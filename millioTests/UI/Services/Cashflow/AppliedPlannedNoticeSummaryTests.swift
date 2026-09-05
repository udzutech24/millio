//
//  AppliedPlannedNoticeSummaryTests.swift
//  millioTests
//
//  Гейт фазы 3 «уведомление о применённых плановых операциях» — то, что решает не вёрстка:
//  1) порядок строк по валютам детерминирован (иначе строки прыгают между отрисовками);
//  2) валюта с нулевым нетто остаётся в списке (ноль ≠ «ничего не было»);
//  3) счётчики и «и ещё N» берутся из агрегата и переживают потолок деталей;
//  4) порядок деталей — журнальный, не пересортированный;
//  5) знак суммы явный: доход читается как «+», а не как отсутствие минуса.
//

import Foundation
import Testing
@testable import millio

@Suite("AppliedPlannedNoticeSummary — модель листа сводки")
struct AppliedPlannedNoticeSummaryTests {

    // MARK: - Harness

    private func entry(
        title: String = "Аренда",
        accountName: String = "Основной счёт",
        amount: Decimal,
        currencyCode: String = "RUB",
        kind: AppliedPlannedEntry.Kind = .scheduled
    ) -> AppliedPlannedEntry {
        AppliedPlannedEntry(
            title: title,
            accountName: accountName,
            amount: amount,
            currencyCode: currencyCode,
            appliedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: kind
        )
    }

    private func digest(_ entries: [AppliedPlannedEntry]) -> AppliedPlannedDigest {
        var digest = AppliedPlannedDigest()
        for entry in entries { digest.accumulate(entry) }
        return digest
    }

    // MARK: - Порядок валют

    @Test("Строки валют отсортированы по модулю нетто, при равенстве — по коду")
    func currencyLinesAreOrderedByMagnitudeThenCode() {
        let summary = AppliedPlannedNoticeSummary(digest: digest([
            entry(amount: -500, currencyCode: "USD"),
            entry(amount: 12_000, currencyCode: "RUB"),
            entry(amount: 500, currencyCode: "EUR"),
            entry(amount: -80, currencyCode: "CNY")
        ]))

        #expect(summary.currencyLines.map(\.currencyCode) == ["RUB", "EUR", "USD", "CNY"])
    }

    @Test("Один и тот же digest даёт один и тот же порядок строк при повторных построениях")
    func currencyLineOrderIsStableAcrossRebuilds() {
        let source = digest([
            entry(amount: 100, currencyCode: "RUB"),
            entry(amount: 100, currencyCode: "USD"),
            entry(amount: 100, currencyCode: "EUR"),
            entry(amount: 100, currencyCode: "GBP"),
            entry(amount: 100, currencyCode: "CNY")
        ])

        // Словарь `totalsByCurrency` порядка не гарантирует: без сортировки этот тест краснел бы
        // не каждый прогон, а через раз — поэтому строим модель много раз подряд.
        let reference = AppliedPlannedNoticeSummary(digest: source).currencyLines.map(\.currencyCode)
        #expect(reference == ["CNY", "EUR", "GBP", "RUB", "USD"])
        for _ in 0..<50 {
            #expect(AppliedPlannedNoticeSummary(digest: source).currencyLines.map(\.currencyCode) == reference)
        }
    }

    @Test("Валюта с нулевым нетто остаётся строкой: доход и расход сошлись, но операции были")
    func zeroNetCurrencyIsKept() {
        let summary = AppliedPlannedNoticeSummary(digest: digest([
            entry(amount: 1_000, currencyCode: "RUB"),
            entry(amount: -1_000, currencyCode: "RUB")
        ]))

        #expect(summary.currencyLines.count == 1)
        #expect(summary.currencyLines.first?.net == 0)
        #expect(summary.totalCount == 2)
        #expect(summary.incomeCount == 1)
        #expect(summary.expenseCount == 1)
    }

    // MARK: - Потолок деталей

    @Test("Счётчики и «и ещё N» считаются от агрегата, а не от обрезанных деталей")
    func aggregateSurvivesDetailsCap() {
        let entries = (0..<120).map { index in
            entry(title: "Операция \(index)", amount: index.isMultiple(of: 2) ? 100 : -100)
        }
        let summary = AppliedPlannedNoticeSummary(digest: digest(entries))

        #expect(summary.totalCount == 120)
        #expect(summary.details.count == AppliedPlannedDigest.detailsCap)
        #expect(summary.truncatedCount == 120 - AppliedPlannedDigest.detailsCap)
        #expect(summary.incomeCount == 60)
        #expect(summary.expenseCount == 60)
    }

    @Test("Порядок деталей — журнальный, модель его не пересортировывает")
    func detailsKeepJournalOrder() {
        let entries = (0..<5).map { entry(title: "Операция \($0)", amount: Decimal($0 + 1)) }
        let summary = AppliedPlannedNoticeSummary(digest: digest(entries))

        #expect(summary.details.map(\.title) == ["Операция 0", "Операция 1", "Операция 2", "Операция 3", "Операция 4"])
        #expect(summary.truncatedCount == 0)
    }

    @Test("Пустой digest — пустая модель: показывать нечего")
    func emptyDigestProducesEmptySummary() {
        let summary = AppliedPlannedNoticeSummary(digest: AppliedPlannedDigest())

        #expect(summary.totalCount == 0)
        #expect(summary.currencyLines.isEmpty)
        #expect(summary.details.isEmpty)
        #expect(summary.truncatedCount == 0)
    }

    // MARK: - Формат суммы

    @Test("Знак суммы явный: доход с плюсом, расход с минусом, ноль без знака")
    func signedAmountCarriesExplicitSign() {
        let income = AppliedPlannedNoticeAmountFormat.signedAmount(1_200, currencyCode: "RUB")
        let expense = AppliedPlannedNoticeAmountFormat.signedAmount(-350, currencyCode: "RUB")
        let zero = AppliedPlannedNoticeAmountFormat.signedAmount(0, currencyCode: "RUB")

        #expect(income.hasPrefix("+"))
        #expect(expense.hasPrefix("\u{2212}"))
        #expect(!zero.hasPrefix("+") && !zero.hasPrefix("\u{2212}"))
        #expect(income.hasSuffix("₽"))
        #expect(income.contains("1"))
        #expect(income.contains("200"))
    }

    @Test("Дробная часть не теряется: проценты по вкладу меньше единицы не превращаются в ноль")
    func fractionalInterestIsNotRoundedAway() {
        let formatted = AppliedPlannedNoticeAmountFormat.signedAmount(Decimal(string: "0.37")!, currencyCode: "RUB")

        #expect(formatted.hasPrefix("+"))
        #expect(formatted.contains("37"))
    }

    @Test("Неизвестный код валюты показывается кодом, а не подменяется чужим символом")
    func unknownCurrencyFallsBackToCode() {
        #expect(AppliedPlannedNoticeAmountFormat.symbol(for: "XYZ") == "XYZ")
        #expect(AppliedPlannedNoticeAmountFormat.symbol(for: "RUB") == "₽")
    }
}
