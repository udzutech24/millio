//
//  CashflowScheduledTransactionsView.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import EventKitUI
import SwiftUI

struct CashflowScheduledTransactionsView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(ToastCenter.self) private var toastCenter
    let kind: CashflowCategoryKind
    let mode: CashflowScheduledTransactionsMode

    @State private var searchText: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var createRecurrenceRule: CashflowRecurrenceRule = .none
    @State private var createInitialDate: Date? = nil
    @State private var editingTransaction: CashflowTransaction?
    @State private var pendingDeleteTransaction: CashflowTransaction?
    @State private var showDeleteAlert: Bool = false
    @State private var plannerDisplayMode: PlannerDisplayMode = .calendar
    @State private var plannerMonthAnchor: Date = CashflowScheduledTransactionsView.monthStart(for: Date())
    @State private var selectedPlannerDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var pendingCalendarExportEntry: CashflowScheduledEntry?
    @State private var calendarExportPayload: AppleCalendarEventExportPayload?
    @State private var isCalendarExportInProgress = false
    @State private var calendarEventStore = AppleCalendarEventStore()

    private enum PlannerDisplayMode: String, CaseIterable, Identifiable {
        case calendar
        case list

        var id: String { rawValue }
    }

    private var recurringTransactions: [CashflowTransaction] {
        viewModel.recurringTemplates(for: kind)
    }

    private var plannedTransactions: [CashflowTransaction] {
        viewModel.plannedOneTimeTransactions(for: kind)
    }

    private var plannerEntries: [CashflowScheduledEntry] {
        viewModel.scheduledPlannerEntries(for: kind)
    }

    private var plannerCalendarEntries: [CashflowScheduledEntry] {
        viewModel.scheduledCalendarEntries(for: kind, month: plannerMonthAnchor)
    }

    private var filteredTransactions: [CashflowTransaction] {
        switch mode {
        case .recurring:
            return recurringTransactions.filter(matchesSearch)
        case .planner:
            return plannedTransactions.filter(matchesSearch)
        }
    }

    private var filteredRecurringTransactions: [CashflowTransaction] {
        recurringTransactions.filter(matchesSearch)
    }

    private var filteredPlannedTransactions: [CashflowTransaction] {
        plannedTransactions.filter(matchesSearch)
    }

    private var filteredPlannerEntries: [CashflowScheduledEntry] {
        plannerEntries.filter(matchesSearch)
    }

    private var filteredPlannerCalendarEntries: [CashflowScheduledEntry] {
        plannerCalendarEntries.filter(matchesSearch)
    }

    private var selectedDayEntries: [CashflowScheduledEntry] {
        filteredPlannerCalendarEntries.filter {
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: selectedPlannerDate)
        }
    }

    private var plannerOverviewEntry: CashflowScheduledEntry? {
        filteredPlannerEntries.first
    }

    /// Сумма повторяющихся поступлений/расходов в месяц, сгруппированная по валюте.
    private var recurringMonthlyTotals: [(currency: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for t in recurringTransactions {
            let monthly: Double
            switch t.recurrenceRule {
            case .monthly:     monthly = t.amount
            case .quarterly:   monthly = t.amount / 3
            case .semiannual:  monthly = t.amount / 6
            case .yearly:      monthly = t.amount / 12
            case .weekly:      monthly = t.amount * (52.0 / 12.0)
            case .none:        monthly = t.amount
            }
            totals[t.currency, default: 0] += monthly
        }
        return totals.map { (currency: $0.key, amount: $0.value) }
            .sorted { $0.currency < $1.currency }
    }

    private var plannerMonthlyCount: Int {
        filteredPlannerEntries.filter { $0.kind == .recurringMonthly }.count
    }

    private var plannerOneTimeCount: Int {
        filteredPlannerEntries.filter { $0.kind == .oneTimePlanned }.count
    }

    private var listIsEmpty: Bool {
        switch mode {
        case .recurring:
            return filteredTransactions.isEmpty
        case .planner:
            return filteredRecurringTransactions.isEmpty && filteredPlannedTransactions.isEmpty
        }
    }

    var body: some View {
        ZStack {
            GradientBackground()

            if listIsEmpty && mode == .recurring {
                VStack(spacing: 12) {
                    searchSection
                    emptyState
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            } else {
                contentList
            }
        }
        .navigationTitle(mode.navigationTitle(for: kind))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if mode == .planner {
                    Menu {
                        Button(L("cashflow.scheduled.create_picker.monthly")) {
                            createMonthlyTransaction()
                        }
                        Button(L("cashflow.scheduled.create_picker.one_time")) {
                            createPlannedForSelectedDate()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                } else {
                    Button {
                        handleCreateTapped()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CashflowTransactionEditorView(
                viewModel: viewModel,
                transactionType: kind.transactionType,
                showsTransactionTypeSection: false,
                showsRecurrenceSection: mode.showsRecurrenceSection,
                customNavigationTitle: mode.createNavigationTitle(for: kind, recurrenceRule: createRecurrenceRule),
                initialRecurrenceRule: createRecurrenceRule,
                initialTransactionDate: createInitialDate,
                onSave: { showCreateSheet = false }
            )
        }
        .sheet(item: $editingTransaction) { transaction in
            CashflowTransactionEditorView(
                viewModel: viewModel,
                transaction: transaction,
                showsTransactionTypeSection: false,
                showsRecurrenceSection: mode.showsRecurrenceSection,
                customNavigationTitle: mode.editNavigationTitle(for: kind, transaction: transaction),
                onSave: { editingTransaction = nil }
            )
        }
        .alert(L("cashflow.scheduled.delete_transaction.title"), isPresented: $showDeleteAlert) {
            Button(L("cashflow.common.cancel"), role: .cancel) {
                pendingDeleteTransaction = nil
            }
            Button(L("cashflow.history.detail.delete"), role: .destructive) {
                guard let transactionToDelete = pendingDeleteTransaction else { return }
                viewModel.handle(.deleteTransaction(transactionToDelete, recalculate: true))
                pendingDeleteTransaction = nil
                updatePlannerSelectionIfNeeded()
            }
        } message: {
            Text(L("cashflow.scheduled.delete_transaction.message"))
        }
        .confirmationDialog(
            L("cashflow.calendar_export.confirmation.title", defaultValue: "Add to Calendar?"),
            isPresented: Binding(
                get: { pendingCalendarExportEntry != nil },
                set: { if !$0 { pendingCalendarExportEntry = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("cashflow.calendar_export.confirmation.action", defaultValue: "Continue")) {
                guard let entry = pendingCalendarExportEntry else { return }
                pendingCalendarExportEntry = nil
                beginCalendarExport(for: entry)
            }
            Button(L("cashflow.common.cancel"), role: .cancel) {
                pendingCalendarExportEntry = nil
            }
        } message: {
            Text(L(
                "cashflow.calendar_export.confirmation.message",
                defaultValue: "Millio will open Apple Calendar. Changes to this transaction later will not update the exported event."
            ))
        }
        .sheet(item: $calendarExportPayload) { payload in
            AppleCalendarEventEditorSheet(eventStore: calendarEventStore, payload: payload) { action in
                calendarExportPayload = nil
                if action == .saved {
                    toastCenter.show(message: L(
                        "cashflow.calendar_export.saved",
                        defaultValue: "Event saved to Calendar"
                    ))
                }
            }
        }
        .onAppear {
            configurePlannerFocusIfNeeded()
        }
        .onChange(of: plannerMonthAnchor) { _, _ in
            updatePlannerSelectionIfNeeded()
        }
        .onChange(of: searchText) { _, _ in
            updatePlannerSelectionIfNeeded()
        }
        .onChange(of: viewModel.state.transactions.count) { _, _ in
            updatePlannerSelectionIfNeeded()
        }
    }

    private var contentList: some View {
        List {
            listCard(searchSection)

            switch mode {
            case .recurring:
                recurringContent
            case .planner:
                plannerContent
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private var recurringContent: some View {
        if !recurringTransactions.isEmpty {
            listCard(recurringTotalCard)
        }
        if filteredTransactions.isEmpty {
            listCard(emptyState)
        } else {
            ForEach(filteredTransactions) { transaction in
                transactionRow(transaction)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var recurringTotalCard: some View {
        FinancesGlassCard(accentColor: kind.accentColor, cornerRadius: 20, contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: kind == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(kind.accentColor)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(kind.accentColor.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("cashflow.scheduled.recurring_total.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)

                        Text(L("cashflow.scheduled.recurring_total.subtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                    }

                    Spacer(minLength: 8)
                }

                Divider()
                    .overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recurringMonthlyTotals.indices, id: \.self) { idx in
                        let entry = recurringMonthlyTotals[idx]
                        HStack(alignment: .firstTextBaseline) {
                            Text(L("cashflow.scheduled.recurring_total.per_month"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)

                            Spacer()

                            Text(totalAmountString(amount: entry.amount, currency: entry.currency))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var plannerContent: some View {
        listCard(plannerOverviewSection)
        if kind == .expense {
            listCard(subscriptionsNavRow)
        }
        listCard(plannerModePicker)

        if plannerDisplayMode == .calendar {
            listCard(plannerCalendarSection)
            listCard(selectedDaySummarySection)

            if selectedDayEntries.isEmpty {
                listCard(dayAgendaEmptyState)
            } else {
                ForEach(selectedDayEntries) { entry in
                    transactionRow(entry.transaction, entryKind: entry.kind, scheduledDate: entry.scheduledDate, scheduledEntry: entry)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        } else {
            if filteredRecurringTransactions.isEmpty && filteredPlannedTransactions.isEmpty {
                listCard(emptyState)
            } else {
                if !filteredRecurringTransactions.isEmpty {
                    plannerSectionHeader(plannerMonthlySectionTitle)
                    ForEach(filteredPlannerEntries.filter { $0.kind == .recurringMonthly }) { entry in
                        transactionRow(entry.transaction, entryKind: entry.kind, scheduledDate: entry.scheduledDate, scheduledEntry: entry)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if !filteredPlannedTransactions.isEmpty {
                    plannerSectionHeader(plannerOneTimeSectionTitle)
                    ForEach(filteredPlannerEntries.filter { $0.kind == .oneTimePlanned }) { entry in
                        transactionRow(entry.transaction, entryKind: entry.kind, scheduledDate: entry.scheduledDate, scheduledEntry: entry)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
    }

    private func listCard<Content: View>(_ content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func plannerSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            TextField(L("cashflow.scheduled.search_transaction"), text: $searchText)
                .textInputAutocapitalization(.words)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var plannerOverviewSection: some View {
        FinancesGlassCard(accentColor: kind.accentColor, cornerRadius: 20, contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            plannerOverviewTitle
                        )
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                        if let nextEntry = plannerOverviewEntry {
                            Text(nextPlannerHeadline(for: nextEntry))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        } else {
                            Text(L("cashflow.scheduled.overview.empty"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Spacer(minLength: 12)

                    Image(systemName: kind == .expense ? "calendar.badge.clock" : "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(kind.accentColor)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(kind.accentColor.opacity(0.14))
                        )
                }

                HStack(spacing: 10) {
                    plannerMetricCard(
                        title: L("cashflow.scheduled.overview.next"),
                        value: plannerOverviewEntry.map { shortDate($0.scheduledDate) } ?? "-"
                    )
                    plannerMetricCard(
                        title: plannerMonthlySectionTitle,
                        value: "\(plannerMonthlyCount)"
                    )
                    plannerMetricCard(
                        title: plannerOneTimeSectionTitle,
                        value: "\(plannerOneTimeCount)"
                    )
                }
            }
        }
    }

    private func plannerMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var subscriptionsNavRow: some View {
        NavigationLink {
            UserSubscriptionsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.subscriptionsGradient.first ?? .orange)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill((AppColors.subscriptionsGradient.first ?? .orange).opacity(0.14))
                    )

                Text(L("subscriptions.title", defaultValue: "Subscriptions"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var plannerModePicker: some View {
        HStack(spacing: 8) {
            ForEach(PlannerDisplayMode.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        plannerDisplayMode = item
                    }
                } label: {
                    Text(itemTitle(item))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(plannerDisplayMode == item ? Color.black : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(plannerDisplayMode == item ? Color.white : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var plannerCalendarSection: some View {
        FinancesGlassCard(accentColor: kind.accentColor, cornerRadius: 20, contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button {
                        guard let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: plannerMonthAnchor) else { return }
                        plannerMonthAnchor = previousMonth
                    } label: {
                        calendarChevron(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(plannerMonthTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Button {
                        guard let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: plannerMonthAnchor) else { return }
                        plannerMonthAnchor = nextMonth
                    } label: {
                        calendarChevron(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    ForEach(rotatedWeekdaySymbols(), id: \.self) { symbol in
                        Text(symbol.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(0..<leadingBlankDays, id: \.self) { _ in
                        Color.clear
                            .frame(height: 48)
                    }

                    ForEach(daysInPlannerMonth(), id: \.self) { day in
                        plannerDayCell(day)
                    }
                }
            }
        }
    }

    private func calendarChevron(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
            )
    }

    private func plannerDayCell(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedPlannerDate)
        let isToday = Calendar.current.isDateInToday(day)
        let entryCount = entriesCount(on: day)

        return Button {
            selectedPlannerDate = Calendar.current.startOfDay(for: day)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? kind.accentColor.opacity(0.24) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? kind.accentColor.opacity(0.85) : Color.white.opacity(0.10), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    Text(dayNumber(day))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            isSelected
                                ? AppColors.textPrimary
                                : AppColors.textPrimary.opacity(isCurrentMonth(day) ? 1.0 : 0.4)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)

                    Circle()
                        .fill(entryCount > 0 ? kind.accentColor : (isToday ? Color.white.opacity(0.7) : Color.clear))
                        .frame(width: 6, height: 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 8)

                if entryCount > 0 {
                    Text("\(entryCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(kind.accentColor)
                        )
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(height: 52)
        }
        .buttonStyle(.plain)
    }

    private var dayAgendaEmptyState: some View {
        FinancesGlassCard(cornerRadius: 20, contentPadding: EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("cashflow.scheduled.day_agenda.empty_title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

                Text(L("cashflow.scheduled.day_agenda.empty_subtitle"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedDaySummarySection: some View {
        FinancesGlassCard(accentColor: kind.accentColor, cornerRadius: 20, contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: L("cashflow.scheduled.day_agenda.title"), formatDayHeader(selectedPlannerDate)))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(selectedDaySummaryText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button {
                        createPlannedForSelectedDate()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text(L("cashflow.scheduled.day_agenda.empty.add_here"))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            Capsule(style: .continuous)
                                .fill(kind.accentColor.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: mode.emptyIcon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)

            Text(mode.emptyTitle(for: kind))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Button(mode.createButtonTitle(for: kind)) {
                handleCreateTapped()
            }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 28)
    }

    private func transactionRow(
        _ transaction: CashflowTransaction,
        entryKind: CashflowScheduledEntryKind? = nil,
        scheduledDate: Date? = nil,
        scheduledEntry: CashflowScheduledEntry? = nil
    ) -> some View {
        let resolvedKind = entryKind ?? (transaction.isRecurringTemplate ? .recurringMonthly : .oneTimePlanned)

        return FinancesGlassCard(accentColor: kind.accentColor) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        CashflowCategoryIconView(
                            icon: icon(for: transaction),
                            fontSize: 13,
                            fontWeight: .semibold,
                            tint: AnyShapeStyle(AppColors.textSecondary)
                        )
                        Text(title(for: transaction))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.leading)

                        if let badgeTitle = badgeTitle(for: resolvedKind, transaction: transaction) {
                            Text(badgeTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                    }

                    Text(subtitle(for: transaction, entryKind: resolvedKind, scheduledDate: scheduledDate))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Text(amountString(for: transaction))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingTransaction = transaction
        }
        .contextMenu {
            if let scheduledEntry, canExportToCalendar(scheduledEntry) {
                Button {
                    pendingCalendarExportEntry = scheduledEntry
                } label: {
                    Label(
                        L("cashflow.calendar_export.action", defaultValue: "Add to Calendar"),
                        systemImage: "calendar.badge.plus"
                    )
                }
                .disabled(isCalendarExportInProgress)
            }
            Button(L("cashflow.common.edit")) {
                editingTransaction = transaction
            }
            Button(L("cashflow.history.detail.delete"), role: .destructive) {
                requestDelete(transaction)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestDelete(transaction)
            } label: {
                Label(L("cashflow.history.detail.delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let scheduledEntry, canExportToCalendar(scheduledEntry) {
                Button {
                    pendingCalendarExportEntry = scheduledEntry
                } label: {
                    Label(
                        L("cashflow.calendar_export.action", defaultValue: "Add to Calendar"),
                        systemImage: "calendar.badge.plus"
                    )
                }
                .tint(kind.accentColor)
                .disabled(isCalendarExportInProgress)
            }
        }
    }

    private func canExportToCalendar(_ entry: CashflowScheduledEntry) -> Bool {
        guard mode == .planner else { return false }
        return AppleCalendarEventExportEligibility.isEligible(
            scheduledDate: entry.scheduledDate,
            now: Date(),
            calendar: .current
        )
    }

    private func beginCalendarExport(for entry: CashflowScheduledEntry) {
        guard !isCalendarExportInProgress, canExportToCalendar(entry) else { return }
        guard let payload = calendarPayload(for: entry) else {
            toastCenter.show(message: L(
                "cashflow.calendar_export.unavailable",
                defaultValue: "Calendar event could not be prepared"
            ))
            return
        }

        isCalendarExportInProgress = true
        Task { @MainActor in
            let authorizer = AppleCalendarEventExportAuthorizer(eventStore: calendarEventStore)
            let state = await authorizer.authorizeForExport()
            isCalendarExportInProgress = false

            switch state {
            case .granted:
                calendarExportPayload = payload
            case .denied, .restricted:
                toastCenter.show(message: L(
                    "cashflow.calendar_export.access_denied",
                    defaultValue: "Calendar access is unavailable. Allow it in iPhone Settings to add an event."
                ))
            case .notDetermined:
                toastCenter.show(message: L(
                    "cashflow.calendar_export.unavailable",
                    defaultValue: "Calendar event could not be prepared"
                ))
            }
        }
    }

    private func calendarPayload(for entry: CashflowScheduledEntry) -> AppleCalendarEventExportPayload? {
        let amount = amountString(for: entry.transaction)
        let title = "\(entry.transaction.transactionType.displayName) — \(amount)"
        return AppleCalendarEventExportPayloadBuilder(calendar: .current).makePayload(
            title: title,
            notes: entry.transaction.note,
            scheduledDate: entry.scheduledDate
        )
    }

    private func handleCreateTapped() {
        switch mode {
        case .recurring:
            createRecurrenceRule = .monthly
            let cal = Calendar.current
            let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
            createInitialDate = cal.date(byAdding: .month, value: 1, to: thisMonthStart) ?? Date()
            showCreateSheet = true
        case .planner:
            createPlannedForSelectedDate()
        }
    }

    private func createMonthlyTransaction() {
        createRecurrenceRule = .monthly
        createInitialDate = selectedPlannerDate
        showCreateSheet = true
    }

    private func createPlannedForSelectedDate() {
        createRecurrenceRule = .none
        createInitialDate = selectedPlannerDate
        showCreateSheet = true
    }

    private func requestDelete(_ transaction: CashflowTransaction) {
        pendingDeleteTransaction = transaction
        showDeleteAlert = true
    }

    private func matchesSearch(_ transaction: CashflowTransaction) -> Bool {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let query = trimmedQuery.lowercased()
        if title(for: transaction).lowercased().contains(query) { return true }
        if subtitle(for: transaction).lowercased().contains(query) { return true }
        if (transaction.note ?? "").lowercased().contains(query) { return true }
        if amountString(for: transaction).lowercased().contains(query) { return true }
        return false
    }

    private func matchesSearch(_ entry: CashflowScheduledEntry) -> Bool {
        matchesSearch(entry.transaction)
        || subtitle(for: entry.transaction, entryKind: entry.kind, scheduledDate: entry.scheduledDate).lowercased().contains(searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func title(for transaction: CashflowTransaction) -> String {
        switch kind {
        case .income:
            return viewModel.incomeCategoryDisplayName(for: transaction.incomeCategoryRaw)
        case .expense:
            return viewModel.expenseCategoryDisplayName(for: transaction.expenseCategoryRaw)
        }
    }

    private func icon(for transaction: CashflowTransaction) -> String {
        switch kind {
        case .income:
            return viewModel.categoryOption(
                for: transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue,
                kind: .income
            ).icon
        case .expense:
            return viewModel.categoryOption(
                for: transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue,
                kind: .expense
            ).icon
        }
    }

    private func subtitle(
        for transaction: CashflowTransaction,
        entryKind: CashflowScheduledEntryKind? = nil,
        scheduledDate: Date? = nil
    ) -> String {
        var parts: [String] = []
        let resolvedKind = entryKind ?? (transaction.isRecurringTemplate ? .recurringMonthly : .oneTimePlanned)
        let plannedDate = scheduledDate ?? transaction.transactionDate

        switch resolvedKind {
        case .recurringMonthly:
            if let nextDate = scheduledDate ?? viewModel.nextOccurrenceDate(for: transaction) {
                parts.append(
                    String(
                        format: L("cashflow.scheduled.subtitle.next_format"),
                        formatDate(nextDate)
                    )
                )
            } else {
                parts.append(
                    String(
                        format: L("cashflow.scheduled.subtitle.start_date_format"),
                        formatDate(plannedDate)
                    )
                )
            }
        case .oneTimePlanned:
            parts.append(
                String(
                    format: L("cashflow.scheduled.subtitle.planned_date_format"),
                    formatDate(plannedDate)
                )
            )
        }

        if let cardName = cardName(for: transaction.cardID) {
            parts.append(
                String(
                    format: L("cashflow.scheduled.subtitle.account_format"),
                    cardName
                )
            )
        }

        if let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            parts.append(note)
        }

        return parts.joined(separator: " • ")
    }

    private func badgeTitle(for kind: CashflowScheduledEntryKind, transaction: CashflowTransaction) -> String? {
        switch kind {
        case .recurringMonthly:
            return transaction.recurrenceRule.displayName
        case .oneTimePlanned:
            return L("cashflow.scheduled.one_time_badge")
        }
    }

    private func amountString(for transaction: CashflowTransaction) -> String {
        totalAmountString(amount: transaction.amount, currency: transaction.currency)
    }

    private func totalAmountString(amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "0"
        return "\(formatted) \(currency)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMM y")
        return formatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    private func formatDayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date)
    }

    private var selectedDaySummaryText: String {
        CashflowScheduledPlannerCopy.daySummaryText(entryCount: selectedDayEntries.count)
    }

    private var plannerMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("LLLL y")
        return formatter.string(from: plannerMonthAnchor)
    }

    private func nextPlannerHeadline(for entry: CashflowScheduledEntry) -> String {
        let category = title(for: entry.transaction)
        let date = shortDate(entry.scheduledDate)
        let prefix: String = entry.kind == .recurringMonthly
            ? entry.transaction.recurrenceRule.displayName
            : L("cashflow.scheduled.overview.one_time_prefix")
        return "\(prefix): \(category) • \(date)"
    }

    private var plannerOverviewTitle: String {
        switch kind {
        case .income:
            return L("cashflow.scheduled.overview.title.income")
        case .expense:
            return L("cashflow.scheduled.overview.title.expense")
        }
    }

    private var plannerMonthlySectionTitle: String {
        L("cashflow.scheduled.section.recurring")
    }

    private var plannerOneTimeSectionTitle: String {
        L("cashflow.scheduled.section.one_time")
    }

    private func itemTitle(_ item: PlannerDisplayMode) -> String {
        switch item {
        case .calendar:
            return L("cashflow.scheduled.display.calendar")
        case .list:
            return L("cashflow.scheduled.display.list")
        }
    }

    private func cardName(for cardID: String?) -> String? {
        guard let cardID else { return nil }
        return viewModel.state.allCards.first(where: { $0.cardUniqueID == cardID })?.name
    }

    private func configurePlannerFocusIfNeeded() {
        guard mode == .planner else { return }
        let focusDate = plannerEntries.first?.scheduledDate ?? Date()
        plannerMonthAnchor = Self.monthStart(for: focusDate)
        selectedPlannerDate = Calendar.current.startOfDay(for: focusDate)
    }

    private func updatePlannerSelectionIfNeeded() {
        guard mode == .planner else { return }

        let calendar = Calendar.current
        let selectedMonthMatches = calendar.isDate(selectedPlannerDate, equalTo: plannerMonthAnchor, toGranularity: .month)
        if selectedMonthMatches,
           filteredPlannerCalendarEntries.contains(where: { calendar.isDate($0.scheduledDate, inSameDayAs: selectedPlannerDate) }) {
            return
        }

        if let firstEntry = filteredPlannerCalendarEntries.first {
            selectedPlannerDate = calendar.startOfDay(for: firstEntry.scheduledDate)
            return
        }

        selectedPlannerDate = calendar.startOfDay(for: plannerMonthAnchor)
    }

    private func entriesCount(on date: Date) -> Int {
        filteredPlannerCalendarEntries.filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }.count
    }

    private func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }

    private func isCurrentMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: plannerMonthAnchor, toGranularity: .month)
    }

    private func daysInPlannerMonth() -> [Date] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: plannerMonthAnchor) ?? DateInterval(start: plannerMonthAnchor, duration: 0)
        var days: [Date] = []
        var cursor = interval.start

        while cursor < interval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return days
    }

    private var leadingBlankDays: Int {
        let calendar = Calendar.current
        guard let firstDay = daysInPlannerMonth().first else { return 0 }
        return (calendar.component(.weekday, from: firstDay) + 5) % 7
    }

    private func rotatedWeekdaySymbols() -> [String] {
        var calendar = Calendar.current
        calendar.locale = AppLocalization.currentAppLocale
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard let first = symbols.first else { return symbols }
        return Array(symbols.dropFirst()) + [first]
    }

    private static func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

enum CashflowScheduledPlannerCopy {
    static func daySummaryText(entryCount: Int, locale: Locale = .autoupdatingCurrent) -> String {
        if entryCount == 0 {
            return AppLocalization.string(
                "cashflow.scheduled.day_agenda.summary.empty",
                locale: locale,
                fallback: "You can add another planned item directly to this date."
            )
        }

        let format = AppLocalization.string(
            "cashflow.scheduled.day_agenda.summary.count",
            locale: locale,
            fallback: "%lld scheduled item(s) on this date. Add another without leaving the calendar."
        )
        return String(format: format, locale: locale, Int64(entryCount))
    }
}

enum CashflowScheduledTransactionsMode: Hashable {
    case recurring
    case planner

    var defaultRecurrenceRule: CashflowRecurrenceRule {
        switch self {
        case .recurring:
            return .monthly
        case .planner:
            return .none
        }
    }

    var showsRecurrenceSection: Bool {
        true
    }

    var emptyIcon: String {
        switch self {
        case .recurring:
            return "repeat.circle"
        case .planner:
            return "calendar.badge.clock"
        }
    }

    func navigationTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return L("cashflow.scheduled.recurring_income")
        case (.recurring, .expense):
            return L("cashflow.scheduled.recurring_expenses")
        case (.planner, .income):
            return L("cashflow.scheduled.planner_income")
        case (.planner, .expense):
            return L("cashflow.scheduled.planner_expenses")
        }
    }

    func createNavigationTitle(for kind: CashflowCategoryKind, recurrenceRule: CashflowRecurrenceRule) -> String {
        if self == .recurring || recurrenceRule != .none {
            switch kind {
            case .income:
                return L("cashflow.scheduled.new_recurring_income")
            case .expense:
                return L("cashflow.scheduled.new_recurring_expense")
            }
        }

        switch kind {
        case .income:
            return L("cashflow.scheduled.new_planned_income")
        case .expense:
            return L("cashflow.scheduled.new_planned_expense")
        }
    }

    func editNavigationTitle(for kind: CashflowCategoryKind, transaction: CashflowTransaction) -> String {
        let recurrenceRule = transaction.recurrenceRule
        return createNavigationTitle(for: kind, recurrenceRule: recurrenceRule)
    }

    func emptyTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return L("cashflow.scheduled.empty.recurring_income")
        case (.recurring, .expense):
            return L("cashflow.scheduled.empty.recurring_expenses")
        case (.planner, .income):
            return L("cashflow.scheduled.empty.planner_income")
        case (.planner, .expense):
            return L("cashflow.scheduled.empty.planner_expenses")
        }
    }

    func createButtonTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return L("cashflow.scheduled.add_recurring_income")
        case (.recurring, .expense):
            return L("cashflow.scheduled.add_recurring_expense")
        case (.planner, .income):
            return L("cashflow.scheduled.add_income_item")
        case (.planner, .expense):
            return L("cashflow.scheduled.add_payment")
        }
    }
}

private extension CashflowCategoryKind {
    var accentColor: Color {
        switch self {
        case .income:
            return AppColors.incomeGradient.first ?? AppColors.brandPrimary
        case .expense:
            return AppColors.expenseGradient.first ?? AppColors.brandPrimary
        }
    }

    var transactionType: CashflowTransactionType {
        switch self {
        case .income:
            return .income
        case .expense:
            return .expense
        }
    }
}
