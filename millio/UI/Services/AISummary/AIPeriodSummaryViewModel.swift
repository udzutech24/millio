//
//  AIPeriodSummaryViewModel.swift
//  millio
//

import Combine
import Foundation
import SwiftUI

/// Локальные агрегаты для сводки. Замыкания вместо ссылок на `CashflowViewModel`/`FinanceViewModel`:
/// сводка ничего не считает сама и не тянет за собой два больших VM в тесты.
struct AIPeriodSummaryDataSource {
    var entries: @MainActor () -> [CashflowConvertedTransaction]
    var currency: @MainActor () -> String
    var balance: @MainActor () -> Double
    /// Расходы по категориям за указанные календарные месяцы, ключ — отображаемое имя категории.
    var expenseCategoryTotals: @MainActor (_ months: [Date]) async -> [String: Double]

    static let empty = AIPeriodSummaryDataSource(
        entries: { [] },
        currency: { "RUB" },
        balance: { 0 },
        expenseCategoryTotals: { _ in [:] }
    )
}

/// Итоги периода: цифры считаются на устройстве и показываются всегда, текст модели — сверху и
/// опционально. Пустого экрана быть не может ни в одном состоянии.
@MainActor
final class AIPeriodSummaryViewModel: ObservableObject {
    @Published private(set) var kind: AIPeriodKind = .month
    @Published private(set) var period: AIPeriodSummaryPeriod
    @Published private(set) var figures: AIPeriodFigures = .zero
    @Published private(set) var currency: String = "RUB"
    @Published private(set) var text: AIPeriodSummaryText?
    @Published private(set) var isLoadingText = false
    /// Цифры есть, формулировки нет: офлайн, ошибка сети или Claude недоступен.
    @Published private(set) var isTextUnavailable = false

    private let dataSource: AIPeriodSummaryDataSource
    private let client: any AIPeriodSummaryClient
    private let cache: AIPeriodSummaryCache
    private let now: () -> Date
    private let calendar: Calendar
    private let locale: () -> Locale

    /// Ключи, по которым запрос уже провалился в этой сессии. Без этого экран долбил бы
    /// эндпоинт при каждом появлении карточки и выжигал лимит 5 запросов в минуту.
    private var failedKeys: Set<String> = []
    private var loadedKey: String?
    private var loadTask: Task<Void, Never>?

    init(
        dataSource: AIPeriodSummaryDataSource,
        client: any AIPeriodSummaryClient,
        cache: AIPeriodSummaryCache = AIPeriodSummaryCache(),
        kind: AIPeriodKind = .month,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: @escaping () -> Locale = { AppLocalization.currentAppLocale }
    ) {
        self.dataSource = dataSource
        self.client = client
        self.cache = cache
        self.kind = kind
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.period = AIPeriodSummaryPeriod.current(kind: kind, now: now())
    }

    // MARK: - Действия

    func select(_ kind: AIPeriodKind) {
        guard kind != self.kind else { return }
        self.kind = kind
        refresh()
    }

    /// Пересчитывает цифры мгновенно и, если для них ещё нет текста, просит формулировку.
    func refresh() {
        recomputeFigures()
        let key = currentCacheKey()
        if let cached = cache.text(forKey: key) {
            applyText(cached, key: key)
            return
        }
        guard loadedKey != key else { return }
        text = nil
        isTextUnavailable = false
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.loadText(key: key) }
    }

    // MARK: - Цифры

    private func recomputeFigures() {
        period = AIPeriodSummaryPeriod.current(kind: kind, now: now())
        currency = dataSource.currency()
        figures = AIPeriodSummaryPayloadBuilder.figures(
            entries: dataSource.entries(),
            period: period,
            now: now(),
            balanceEnd: dataSource.balance(),
            calendar: calendar
        )
    }

    private func currentCacheKey() -> String {
        AIPeriodSummaryPayloadBuilder.cacheKey(
            period: period,
            now: now(),
            figures: figures,
            currency: currency,
            locale: locale(),
            calendar: calendar
        )
    }

    // MARK: - Текст

    private func loadText(key: String) async {
        guard client.isAvailable else {
            isTextUnavailable = true
            return
        }
        guard !failedKeys.contains(key) else {
            isTextUnavailable = true
            return
        }

        isLoadingText = true
        defer { isLoadingText = false }

        let categoryTotals = await dataSource.expenseCategoryTotals(period.months(calendar: calendar))
        guard !Task.isCancelled else { return }

        let request = AIPeriodSummaryPayloadBuilder.makeRequest(
            period: period,
            now: now(),
            figures: figures,
            categoryTotals: categoryTotals,
            currency: currency,
            locale: locale(),
            calendar: calendar
        )

        do {
            let result = try await client.summarize(request)
            guard !Task.isCancelled else { return }
            if result.isEmpty {
                // 200 без формулировки — штатная деградация бэкенда: показываем цифры.
                isTextUnavailable = true
                loadedKey = key
            } else {
                cache.store(result, forKey: key)
                applyText(result, key: key)
            }
        } catch {
            guard !Task.isCancelled else { return }
            failedKeys.insert(key)
            isTextUnavailable = true
        }
    }

    private func applyText(_ value: AIPeriodSummaryText, key: String) {
        text = value
        loadedKey = key
        isTextUnavailable = false
        isLoadingText = false
    }
}
