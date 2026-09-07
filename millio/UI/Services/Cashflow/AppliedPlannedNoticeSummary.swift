//
//  AppliedPlannedNoticeSummary.swift
//  millio
//
//  Презентационная модель листа «Пока вас не было».
//  Фаза 3 плана plans/2026-09-05__planned-operations-applied-notice.md.
//
//  Вынесена из вью по одной причине: `AppliedPlannedDigest.totalsByCurrency` — словарь, а словарь
//  отдаёт свои пары в произвольном порядке. Без явной сортировки строки валют переставлялись бы
//  между отрисовками одного и того же листа.
//

import Foundation

// MARK: - AppliedPlannedNoticeSummary

/// Что именно рисует лист сводки: строки по валютам в детерминированном порядке,
/// счётчики направлений и список деталей с «и ещё N».
struct AppliedPlannedNoticeSummary: Equatable {

    /// Нетто по одной валюте. Конвертации нет намеренно: курса на момент каждого применения у нас
    /// нет, а сложить рубли с юанями «примерно» — соврать в цифре, которую читают как факт.
    struct CurrencyLine: Identifiable, Equatable {
        let currencyCode: String
        let net: Decimal

        var id: String { currencyCode }
    }

    let totalCount: Int
    let currencyLines: [CurrencyLine]

    /// Счётчики берутся из агрегата, а не считаются по `details`: деталей максимум 50,
    /// и при большем числе применений подсчёт по списку занизил бы оба числа.
    /// По этой же причине счётчики общие, а не по каждой валюте — журнал их per-currency не хранит.
    let incomeCount: Int
    let expenseCount: Int

    /// Порядок ровно тот, в котором записи легли в журнал. По `appliedAt` не сортируем:
    /// у процентов по вкладу это дата начисления, у остальных — момент применения,
    /// общая сортировка перемешала бы две разные шкалы времени.
    let details: [AppliedPlannedEntry]

    /// Сколько применений не поместилось в детали — строка «и ещё N».
    let truncatedCount: Int

    init(digest: AppliedPlannedDigest) {
        totalCount = digest.totalCount
        incomeCount = digest.incomeCount
        expenseCount = digest.expenseCount
        details = digest.details
        truncatedCount = digest.truncatedCount
        currencyLines = Self.sortedCurrencyLines(digest.totalsByCurrency)
    }

    /// Сначала самые крупные по модулю суммы, при равенстве — по коду валюты.
    /// Валюта с нулевым нетто в списке остаётся: ноль здесь значит «начисления и списания сошлись»,
    /// а не «ничего не происходило», и молча убрать строку — потерять факт применения.
    private static func sortedCurrencyLines(_ totals: [String: Decimal]) -> [CurrencyLine] {
        totals
            .map { CurrencyLine(currencyCode: $0.key, net: $0.value) }
            .sorted { lhs, rhs in
                let lhsMagnitude = abs(lhs.net)
                let rhsMagnitude = abs(rhs.net)
                if lhsMagnitude != rhsMagnitude { return lhsMagnitude > rhsMagnitude }
                return lhs.currencyCode < rhs.currencyCode
            }
    }
}

// MARK: - AppliedPlannedNoticeAmountFormat

/// Денежная строка сводки: знак ставим сами, а не отдаём `NumberFormatter`, потому что доход
/// обязан читаться как «+», а не как отсутствие минуса.
enum AppliedPlannedNoticeAmountFormat {

    static func symbol(for currencyCode: String) -> String {
        MonetaCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
    }

    /// «+1 200 ₽» / «−350 ₽» / «0 ₽». Дробная часть показывается только когда она есть:
    /// проценты по вкладу бывают меньше единицы, и округление до целого превратило бы их в «0».
    static func signedAmount(_ amount: Decimal, currencyCode: String) -> String {
        let sign: String
        if amount > 0 {
            sign = "+"
        } else if amount < 0 {
            sign = "\u{2212}"
        } else {
            sign = ""
        }
        return sign + magnitude(amount) + "\u{00A0}" + symbol(for: currencyCode)
    }

    private static func magnitude(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let value = NSDecimalNumber(decimal: abs(amount))
        return formatter.string(from: value) ?? "0"
    }
}
