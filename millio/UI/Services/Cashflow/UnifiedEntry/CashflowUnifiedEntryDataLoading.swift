//
//  CashflowUnifiedEntryDataLoading.swift
//  millio
//
//  Месячный срез экрана быстрого ввода (суммы, бюджетный снапшот, кэш) и
//  бюджетные хаптики. Вынесено из CashflowUnifiedEntryView без изменения
//  поведения (Ф5 плана entry-screen-simplify).
//

import SwiftUI
import UIKit

extension CashflowCategoryTransactionSheet {
    private func handleBudgetThresholdHaptics(
        previousSnapshot: BudgetProgressSnapshot?,
        newSnapshot: BudgetProgressSnapshot?,
        previousCategorySteps: [String: Int]
    ) {
        handleMonthlyBudgetHaptic(previousSnapshot: previousSnapshot, newSnapshot: newSnapshot)
        handleCategoryBudgetHaptics(newSnapshot: newSnapshot, previousSteps: previousCategorySteps)
    }

    private func handleMonthlyBudgetHaptic(
        previousSnapshot: BudgetProgressSnapshot?,
        newSnapshot: BudgetProgressSnapshot?
    ) {
        guard kind == .expense else { return }
        guard let newSnapshot else {
            lastBudgetHapticStep = -1
            return
        }

        let previousStep = previousSnapshot.map { BudgetThresholdHapticsPlan.step(for: $0.progress) } ?? -1
        let newStep = BudgetThresholdHapticsPlan.step(for: newSnapshot.progress)
        lastBudgetHapticStep = newStep
        guard newStep > previousStep else { return }

        if newStep >= 2 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            UIImpactFeedbackGenerator(style: newStep == 1 ? .medium : .light).impactOccurred()
        }
    }

    private func handleCategoryBudgetHaptics(
        newSnapshot: BudgetProgressSnapshot?,
        previousSteps: [String: Int]
    ) {
        guard kind == .expense else { return }
        guard let newSnapshot else {
            lastCategoryBudgetSteps = [:]
            return
        }

        var updatedSteps: [String: Int] = [:]
        var strongestEscalation: Int = -1

        for item in newSnapshot.categorySnapshots {
            let newStep = BudgetThresholdHapticsPlan.step(for: item.progress)
            let previousStep = previousSteps[item.categoryRawValue] ?? -1
            updatedSteps[item.categoryRawValue] = newStep
            if newStep > previousStep {
                strongestEscalation = max(strongestEscalation, newStep)
            }
        }

        lastCategoryBudgetSteps = updatedSteps

        guard strongestEscalation >= 0 else { return }
        if strongestEscalation >= 2 {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func reloadMonthlyTotal(focusingOn categoryRawValue: String? = nil, forceRefresh: Bool = false) {
        monthTotalTask?.cancel()
        if forceRefresh || categoryRawValue != nil {
            snapshotRevision += 1
            snapshotCache.removeAll()
        }
        let requestedMonth = selectedMonth
        let requestedCurrency = viewModel.state.displayCurrency
        let cacheKey = CashflowUnifiedEntrySnapshotKey(
            kindRawValue: String(describing: kind.categoryKind),
            monthStart: selectedMonth,
            currency: requestedCurrency,
            revision: snapshotRevision
        )
        monthTotalTask = Task {
            let signpostID = CashflowUnifiedEntryTelemetry.beginMonthlySnapshot(kind: kind.categoryKind)
            var signpostCategoryCount = 0
            defer {
                CashflowUnifiedEntryTelemetry.endMonthlySnapshot(
                    signpostID,
                    categoryCount: signpostCategoryCount,
                    wasCancelled: Task.isCancelled
                )
            }
            await MainActor.run {
                isLoadingMonthlyTotal = true
            }

            let snapshot: CashflowUnifiedEntrySnapshot
            if let cached = await snapshotCache.value(for: cacheKey) {
                snapshot = cached
            } else {
                snapshot = await viewModel.unifiedEntrySnapshot(
                    for: kind.categoryKind,
                    month: requestedMonth,
                    in: requestedCurrency
                )
                guard !Task.isCancelled else { return }
                await snapshotCache.insert(snapshot, for: cacheKey)
            }
            let total = snapshot.total
            let totalsByCategory = snapshot.categoryTotals
            signpostCategoryCount = totalsByCategory.count

            guard !Task.isCancelled, requestedMonth == selectedMonth,
                  requestedCurrency == viewModel.state.displayCurrency else { return }
            await MainActor.run {
                let previousCategoryTotals = categoryTotals
                let previousBudgetSnapshot = budgetSnapshot
                let previousCategorySteps = lastCategoryBudgetSteps
                let shouldAnimateValueUpdate = hasCompletedInitialLoad || categoryRawValue != nil
                let feedbackPlan = CashflowCategoryUpdateFeedbackPlan.make(
                    for: categoryRawValue,
                    previousTotals: previousCategoryTotals,
                    updatedTotals: totalsByCategory
                )

                let applyStateUpdate = {
                    monthlyTotal = total
                    categoryTotals = totalsByCategory
                    budgetSnapshot = snapshot.budgetSnapshot
                    categoryBudgetLimits = snapshot.categoryLimits
                    budgetTotalLimit = snapshot.budgetPlan?.totalLimitAmount
                    isLoadingMonthlyTotal = false
                    categoryUpdateFeedbackPlan = feedbackPlan
                }

                if shouldAnimateValueUpdate {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        applyStateUpdate()
                    }
                } else {
                    applyStateUpdate()
                }

                if feedbackPlan != nil {
                    categoryFeedbackSequence += 1
                } else {
                    highlightedCategoryRaw = nil
                    categoryUpdateFeedbackPlan = nil
                }

                hasCompletedInitialLoad = true

                // Keep a stable grid while a user is entering several operations. A save
                // updates amounts, but does not make the tapped card jump under the finger.
                if categoryRawValue == nil {
                    freezeCategoryOrder()
                }

                handleBudgetThresholdHaptics(
                    previousSnapshot: previousBudgetSnapshot,
                    newSnapshot: snapshot.budgetSnapshot,
                    previousCategorySteps: previousCategorySteps
                )
            }
        }
    }

    func freezeCategoryOrder() {
        let base = viewModel.orderedCategoryOptions(for: kind.categoryKind, matching: "")
        let pinned = Set(base.filter {
            viewModel.isCategoryPinned(rawValue: $0.rawValue, kind: kind.categoryKind)
        }.map(\.rawValue))
        let calendar = Calendar.current
        let latest = viewModel.state.transactions.reduce(into: [String: Date]()) { result, transaction in
            guard transaction.transactionType == kind.transactionType,
                  calendar.isDate(transaction.transactionDate, equalTo: selectedMonth, toGranularity: .month) else { return }
            let raw = kind == .income
                ? (transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue)
                : (transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue)
            result[raw] = max(result[raw] ?? .distantPast, transaction.transactionDate)
        }
        frozenCategoryOrder = CashflowCategorySortPolicy.sorted(
            base,
            mode: sortMode,
            pinned: pinned,
            totals: categoryTotals,
            latestActivity: latest
        ).map(\.rawValue)
    }
}
