//
//  DashboardView.swift
//  millio
//

import SwiftUI

struct DashboardView: View {
    var onOpenConverter: () -> Void = {}
    var onOpenCashback: () -> Void = {}

    var onAddIncome: () -> Void = {}
    var onAddExpense: () -> Void = {}
    var onAddTransfer: () -> Void = {}

    var onOpenFinances: () -> Void = {}
    var onOpenDynamics: () -> Void = {}
    var onOpenCashflow: () -> Void = {}

    var totalBalance: Double = 0
    var displayCurrency: String = "RUB"
    var sparklinePoints: [Double] = []
    var weekDelta: (absolute: Double, percent: Double) = (0.0, 0.0)
    var sparklineDaysCount: Int = 7

    var cashflowTotal: Double = 0
    var cashflowIncome: Double = 0
    var cashflowExpense: Double = 0
    var cashflowAssetChange: Double = 0
    var cashflowCurrency: String = "RUB"
    var cashflowPeriodLabel: String = L("dashboard.cashflow.default_period")

    var onOpenHistory: () -> Void = {}
    var onShowProfile: () -> Void = {}
    var onDaysChipTap: (() -> Void)? = nil

    @AppStorage("finance_amount_hidden") private var isAmountHidden: Bool = false
    @State private var activeWidgets: [DashboardWidgetID] = DashboardWidgetStorage.load()
    @State private var isEditing = false
    @State private var showAddWidget = false
    @State private var appeared = false

    private var inactiveWidgets: [DashboardWidgetID] {
        DashboardWidgetID.allCases.filter { !activeWidgets.contains($0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ZStack {
                GradientBackground()

                if isEditing {
                    editModeContent
                        .transition(.opacity)
                    doneButtonOverlay
                } else {
                    normalModeContent(topInset: topInset)
                        .transition(.opacity)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !isEditing else { return }
                    enterEditMode()
                }
        )
        .sheet(isPresented: $showAddWidget) {
            AddWidgetSheet(
                available: inactiveWidgets,
                onAdd: { widget in
                    withAnimation(.spring(response: 0.35)) {
                        activeWidgets.append(widget)
                        DashboardWidgetStorage.save(activeWidgets)
                    }
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Normal Mode

    private func normalModeContent(topInset: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topActionButtons
                    .padding(.top, topInset + 18)
                    .padding(.horizontal, 14)
                    .revealOnAppear(appeared: appeared, index: 0)

                miniAppsSection
                    .padding(.top, 8)
                    .revealOnAppear(appeared: appeared, index: 1)

                if activeWidgets.isEmpty {
                    emptyPlaceholder
                        .revealOnAppear(appeared: appeared, index: 2)
                } else {
                    widgetsSection
                }

                dashboardSettingsButton
                    .padding(.top, 12)
                    .revealOnAppear(appeared: appeared, index: 2 + activeWidgets.count)

                Spacer(minLength: 88)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            guard !appeared else { return }
            appeared = true
        }
    }

    // MARK: - Top Action Buttons

    private var topActionButtons: some View {
        HStack {
            Button {
                onOpenHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                isAmountHidden.toggle()
            } label: {
                Image(systemName: isAmountHidden ? "eye.slash" : "eye")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white.opacity(isAmountHidden ? 0.45 : 0.75))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)

            Button {
                onShowProfile()
            } label: {
                Image("profile")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("root.profileButton")
        }
    }

    // MARK: - Widgets Section

    private var widgetsSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(activeWidgets.enumerated()), id: \.element) { index, widget in
                widgetView(widget)
                    .revealOnAppear(appeared: appeared, index: index + 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func widgetView(_ widget: DashboardWidgetID) -> some View {
        switch widget {
        case .totalBalance:
            TotalBalanceWidget(
                totalBalance: totalBalance,
                displayCurrency: displayCurrency,
                sparklinePoints: sparklinePoints,
                weekDelta: weekDelta,
                sparklineDaysCount: sparklineDaysCount,
                isAmountHidden: isAmountHidden,
                onTap: onOpenFinances,
                onSparklineTap: onOpenDynamics,
                onDaysChipTap: onDaysChipTap
            )
        case .quickActions:
            QuickActionsWidget(
                onAddIncome: onAddIncome,
                onAddExpense: onAddExpense,
                onAddTransfer: onAddTransfer
            )
        case .cashflowSummary:
            CashflowSummaryWidget(
                cashflowTotal: cashflowTotal,
                totalIncome: cashflowIncome,
                totalExpense: cashflowExpense,
                assetValueChange: cashflowAssetChange,
                displayCurrency: cashflowCurrency,
                periodLabel: cashflowPeriodLabel,
                isAmountHidden: isAmountHidden,
                onTap: onOpenCashflow
            )
        case .currencyRates:
            CurrencyRatesWidget(onTap: onOpenConverter)
        }
    }

    // MARK: - Dashboard Settings Button

    private var dashboardSettingsButton: some View {
        Button {
            enterEditMode()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                Text(L("dashboard.settings.button"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.35))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.7))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edit Mode

    private var editModeContent: some View {
        VStack(spacing: 0) {
            miniAppsSection
                .padding(.top, 18)

            List {
                ForEach(activeWidgets) { widget in
                    editRow(for: widget)
                }
                .onMove { from, to in
                    activeWidgets.move(fromOffsets: from, toOffset: to)
                    DashboardWidgetStorage.save(activeWidgets)
                }
                .onDelete { offsets in
                    activeWidgets.remove(atOffsets: offsets)
                    DashboardWidgetStorage.save(activeWidgets)
                }

                if !inactiveWidgets.isEmpty {
                    Button {
                        showAddWidget = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(L("Добавить виджет"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.brandPrimary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.bottom, 60)
        }
    }

    private func editRow(for widget: DashboardWidgetID) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.brandPrimary.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: widget.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
            }
            Text(widget.displayName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
    }

    // MARK: - Done Button Overlay

    private var doneButtonOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button(L("common.done")) {
                    exitEditMode()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.brandPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 18)
            }
            Spacer()
        }
    }

    // MARK: - Empty Placeholder

    private var emptyPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(AppColors.textPrimary.opacity(0.35))

            Text(MainLocalization.text(MainLocalization.dashboardPlaceholderTitle))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary.opacity(0.55))

            Text(MainLocalization.text(MainLocalization.dashboardPlaceholderSubtitle))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppColors.textPrimary.opacity(0.30))
                .multilineTextAlignment(.center)

            Button {
                showAddWidget = true
            } label: {
                Text(L("Добавить виджет"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AppColors.brandPrimary.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 80)
    }

    // MARK: - Mini Apps

    private var miniAppsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                miniAppChip(
                    icon: "chart.line.uptrend.xyaxis",
                    titleKey: MainLocalization.serviceCourses,
                    accentColors: [AppColors.brandPrimary, AppColors.brandPrimary],
                    accessibilityID: "dashboard.chip.courses",
                    action: onOpenConverter
                )
                miniAppChip(
                    icon: "percent",
                    titleKey: MainLocalization.serviceCashback,
                    accentColors: AppColors.cashbackGradient,
                    accessibilityID: "dashboard.chip.cashback",
                    action: onOpenCashback
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
    }

    private func miniAppChip(
        icon: String,
        titleKey: String,
        accentColors: [Color],
        accessibilityID: String = "",
        action: @escaping () -> Void
    ) -> some View {
        let accent = LinearGradient(
            colors: accentColors,
            startPoint: .leading,
            endPoint: .trailing
        )
        // Обводка — всегда плоский однотонный акцент (первый цвет градиента), а не сам градиент:
        // раньше «Курсы» (моноцвет) и «Кешбэк» (двутоновый градиент) выглядели по-разному
        // стилистически, хотя оба чипа — один компонент.
        let strokeColor = accentColors.first ?? Color.white
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(MainLocalization.text(titleKey))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(strokeColor.opacity(0.55), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    // MARK: - Edit Mode Helpers

    private func enterEditMode() {
        withAnimation(.spring(response: 0.3)) {
            isEditing = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func exitEditMode() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            isEditing = false
        }
    }
}

// MARK: - Add Widget Sheet

private struct AddWidgetSheet: View {
    let available: [DashboardWidgetID]
    let onAdd: (DashboardWidgetID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                Group {
                    if available.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(AppColors.incomeGradient.first ?? AppColors.brandPrimary)
                            Text(L("Все виджеты добавлены"))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(available) { widget in
                                    Button {
                                        onAdd(widget)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(AppColors.brandPrimary.opacity(0.18))
                                                    .frame(width: 40, height: 40)
                                                Image(systemName: widget.iconName)
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundStyle(AppColors.brandPrimary)
                                            }

                                            Text(widget.displayName)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(AppColors.textPrimary)

                                            Spacer()

                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(AppColors.brandPrimary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(Color.white.opacity(0.06))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .navigationTitle(L("dashboard.widgets.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("common.close")) { dismiss() }
                        .foregroundStyle(AppColors.brandPrimary)
                }
            }
        }
    }
}

// MARK: - Reveal animation helper

private extension View {
    func revealOnAppear(appeared: Bool, index: Int) -> some View {
        self
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 22)
            .animation(
                .spring(response: 0.52, dampingFraction: 0.82).delay(Double(index) * 0.09),
                value: appeared
            )
    }
}
