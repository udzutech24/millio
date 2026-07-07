//
//  CashflowCategoryCapPolicyTests.swift
//  millioTests
//
//  Фаза 2 редизайна add-flow (§2.2) — cap-логика сетки избранных категорий.
//

import Testing
@testable import millio

struct CashflowCategoryCapPolicyTests {
    @Test("Без запиненных категорий показываем дефолтный минимум — 6")
    func noPinnedFallsBackToMinimum() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 0, totalCount: 20)
        #expect(count == CashflowCategoryCapPolicy.minimumVisible)
    }

    @Test("Меньше минимума запиненных — всё равно добираем до 6")
    func fewPinnedStillFillsToMinimum() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 3, totalCount: 20)
        #expect(count == CashflowCategoryCapPolicy.minimumVisible)
    }

    @Test("Ровно 6 запиненных — показываем ровно их, без добора")
    func exactlyMinimumPinnedShowsExactCount() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 6, totalCount: 20)
        #expect(count == 6)
    }

    @Test("7-8 запиненных — показываем все, потолок не превышен")
    func betweenMinimumAndMaximumShowsAllPinned() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 7, totalCount: 20)
        #expect(count == 7)
    }

    @Test("R4: больше 8 запиненных — жёсткий потолок 8, не показываем все")
    func morePinnedThanMaximumIsHardCapped() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 12, totalCount: 20)
        #expect(count == CashflowCategoryCapPolicy.maximumVisible)
    }

    @Test("R6: каталог меньше минимума — показываем всё, ссылка на 'Все категории' не нужна")
    func catalogSmallerThanMinimumShowsEverything() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 0, totalCount: 4)
        #expect(count == 4)
    }

    @Test("R6: пустой каталог — 0 видимых категорий, без краша")
    func emptyCatalogReturnsZero() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 0, totalCount: 0)
        #expect(count == 0)
    }

    @Test("Все категории запинены и их меньше минимума — cap не превышает totalCount")
    func allPinnedBelowMinimumClampsToTotal() {
        let count = CashflowCategoryCapPolicy.visibleCount(pinnedCount: 4, totalCount: 4)
        #expect(count == 4)
    }
}
