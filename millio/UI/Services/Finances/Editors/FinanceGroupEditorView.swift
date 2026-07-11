//
//  FinanceGroupEditorView.swift
//  millio
//

import SwiftUI

// MARK: - Finance Group Editor View

struct FinanceGroupEditorView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let editingGroupOverride: AccountGroup?
    let presentationStyle: FinanceEditorPresentationStyle
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool
    @State private var selectedColor: Color = Color.blue
    @State private var selectedCurrency: String? = nil
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies = true
    
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    @State private var showCryptoProAlert: Bool = false
    @State private var showDeleteGroupConfirmation: Bool = false
    @State private var pendingAccountDeletion: FinanceAccount? = nil
    @State private var showArchiveBalanceWarning: Bool = false
    @State private var archiveBalanceWarningAmount: Double = 0
    @State private var archiveBalanceWarningCurrency: String = ""
    @State private var pendingAccountDeletionAfterWarning: FinanceAccount? = nil
    @State private var isColorPaletteExpanded: Bool = false
    @State private var selectedIconName: String? = nil
    @State private var showIconPicker: Bool = false

    private let predefinedColors: [Color] = [
        .blue, .cyan, .green, .mint, .purple, .pink,
        .indigo, .orange, .red, .yellow, .teal, .brown
    ]

    init(
        viewModel: FinanceViewModel,
        editingGroupOverride: AccountGroup? = nil,
        presentationStyle: FinanceEditorPresentationStyle = .modal
    ) {
        self.viewModel = viewModel
        self.editingGroupOverride = editingGroupOverride
        self.presentationStyle = presentationStyle
    }
    
    var body: some View {
        let content =
            ZStack {
                GradientBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        nameSection
                        iconSection
                        colorSection
                        currencySection
                        managementSection
                        
                        if let editingGroup = currentEditingGroup {
                            // [Ф5c.7 contract] `orderedAccounts` теперь ПЕРВИЧНЫЙ источник (core,
                            // редактируемый — было read-only). Легаси — fallback-хвост по имени
                            // (invariant 9 §2.1), остаётся read-only (как раньше).
                            let legacyAccounts = viewModel.legacyAccountsMatchingGroupName(editingGroup.name)
                            let coreAccounts = viewModel.orderedAccounts(for: editingGroup)
                            accountsSection(legacyAccounts, coreAccounts: coreAccounts)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()

                FinancesDestructiveConfirmationOverlay(
                    isPresented: showDeleteGroupConfirmation,
                    title: deleteGroupConfirmationTitle,
                    message: deleteGroupConfirmationMessage,
                    confirmTitle: L("finances.common.delete"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: confirmDeleteGroup,
                    onCancel: { showDeleteGroupConfirmation = false }
                )

                FinancesDestructiveConfirmationOverlay(
                    isPresented: pendingAccountDeletion != nil,
                    title: deleteAccountConfirmationTitle,
                    message: deleteAccountConfirmationMessage,
                    confirmTitle: L("finances.common.delete"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: confirmDeleteAccount,
                    onCancel: { pendingAccountDeletion = nil }
                )

                FinancesDestructiveConfirmationOverlay(
                    isPresented: showArchiveBalanceWarning,
                    title: L("finances.archive.balance_warning.title"),
                    message: archiveBalanceWarningMessage,
                    confirmTitle: L("finances.archive.balance_warning.confirm"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: {
                        showArchiveBalanceWarning = false
                        pendingAccountDeletion = pendingAccountDeletionAfterWarning
                        pendingAccountDeletionAfterWarning = nil
                    },
                    onCancel: {
                        showArchiveBalanceWarning = false
                        pendingAccountDeletionAfterWarning = nil
                    }
                )
            }
            .navigationTitle(
                currentEditingGroup == nil
                    ? L("finances.group_editor.nav.new")
                    : L("finances.group_editor.nav.edit")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentationStyle.showsDismissButton {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("finances.common.cancel"))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveGroup()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                    .accessibilityLabel(L("finances.common.save"))
                }
            }
            .onAppear {
                if let editingGroupOverride {
                    viewModel.state.editingGroup = editingGroupOverride
                }
                if let editing = currentEditingGroup {
                    name = editing.name
                    selectedCurrency = editing.displayCurrency
                    selectedIconName = editing.customIconName
                    // Находим соответствующий цвет из predefinedColors по hex-значению
                    let editingColorHex = (editing.colorHex ?? "#FFFFFF").uppercased()
                    if let matchingColor = predefinedColors.first(where: { color in
                        color.toHex().uppercased() == editingColorHex
                    }) {
                        selectedColor = matchingColor
                    } else {
                        // Если точного совпадения нет, используем цвет из группы
                        selectedColor = editing.color
                    }
                }
            }
            .task {
                await loadAvailableCurrencies()
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
                    let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
                    CurrencyPickerView(
                        allCodes: availableCurrencies,
                        searchText: $currencySearchText,
                        selectedCodes: favoriteCodes,
                        favoriteCodes: Set(favoriteCodes),
                        currentSelection: selectedCurrency,
                        primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
                        onToggleFavorite: nil,
                        badgeForCode: { code in
                            guard CurrencySelectionSupport.isCrypto(code), !canUseCrypto else { return nil }
                            return .pro
                        },
                        onSelect: { currency in
                            if CurrencySelectionSupport.isCrypto(currency), !canUseCrypto {
                                showCryptoProAlert = true
                                return
                            }
                            selectedCurrency = currency
                            showCurrencyPicker = false
                        }
                    )
                    .navigationTitle(L("finances.add_account.currency_picker.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("finances.common.cancel")) { showCurrencyPicker = false }
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .premiumUpsellAlert(
                isPresented: $showCryptoProAlert,
                titleKey: "monetization.crypto.pro_title",
                message: .key("monetization.crypto.pro_message"),
                onSubscribe: { router.push(.subscription) }
            )
            .sheet(isPresented: $showIconPicker) {
                // Цвет иконки у группы — это её единый `colorHex` (тот же акцент, что рендерит бейдж),
                // поэтому пикер редактирует общий `selectedColor`, а не отдельное поле цвета.
                AccountIconPickerSheet(iconName: $selectedIconName, iconColor: iconColorBinding)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }

        if presentationStyle.wrapsInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var currentEditingGroup: AccountGroup? {
        editingGroupOverride ?? viewModel.state.editingGroup
    }
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.group_editor.section.name"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField(L("finances.add_account.section.name"), text: $name)
                        .focused($isNameFocused)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)

                    if currentEditingGroup == nil {
                        FinancesRowDivider(leadingPadding: 0)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8) {
                                ForEach(FinanceGroupNameTemplate.allCases) { template in
                                    FinancesPillButton(title: template.title) {
                                        applyNameTemplate(template)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 14)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
    }
    
    private var iconSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            FinancesSectionHeader(title: L("finances.group_editor.section.icon"))
            FinancesGlassCard {
                Button {
                    showIconPicker = true
                } label: {
                    HStack(spacing: AppSpacing.m) {
                        RoundedRectangle(
                            cornerRadius: FinancesMainLayoutPolicy.groupRowTypeIconCornerRadius,
                            style: .continuous
                        )
                        .fill(selectedColor.opacity(0.16))
                        .frame(
                            width: FinancesMainLayoutPolicy.groupRowTypeIconSize,
                            height: FinancesMainLayoutPolicy.groupRowTypeIconSize
                        )
                        .overlay(
                            // nil → нейтральный fallback (иконка «прочее»); заданная кастомная иконка
                            // рендерится в акценте группы (тот же цвет, что бейдж на «Счетах»).
                            AccountIconBadgeView(
                                iconName: selectedIconName,
                                iconColor: selectedColor.toHex(),
                                fallback: "square.grid.2x2.fill",
                                size: FinancesMainLayoutPolicy.groupRowTypeIconSize
                            )
                        )

                        Text(L("finances.group_editor.icon.select"))
                            .font(.millioHeadline)
                            .foregroundStyle(AppColors.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.millioCaption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, AppSpacing.ml)
                    .padding(.horizontal, AppSpacing.l)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Мост цвета для пикера: у группы цвет иконки — это её общий `colorHex`, отдельного поля нет.
    private var iconColorBinding: Binding<String?> {
        Binding(
            get: { selectedColor.toHex() },
            set: { hex in
                // nil у пикера = «дефолтный градиент»; у группы всегда есть цвет — nil игнорируем.
                if let hex { selectedColor = Color(hex: hex) }
            }
        )
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.group_editor.section.color"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isColorPaletteExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(selectedColor)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                                }

                            Text(colorSectionTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()

                            Image(systemName: isColorPaletteExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    if isColorPaletteExpanded {
                        FinancesRowDivider(leadingPadding: 0)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(predefinedColors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isColorPaletteExpanded = false
                                    }
                                } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            if selectedColor == color {
                                                Circle()
                                                    .stroke(AppColors.textPrimary, lineWidth: 3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
    }
    
    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.display_currency.title.primary"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(L("finances.add_account.field.currency"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        if isLoadingCurrencies {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            HStack(spacing: 12) {
                                if selectedCurrency != nil {
                                    Button {
                                        selectedCurrency = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Button {
                                        showCurrencyPicker = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(selectedCurrency ?? viewModel.state.displayCurrency)
                                                .font(.system(size: 16, weight: .semibold))
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundStyle(AppColors.textTertiary)
                                    }
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private func accountsSection(_ accounts: [FinanceAccount], coreAccounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.group_editor.section.accounts"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        if let editingGroup = currentEditingGroup {
                            FinanceAddAccountView(
                                viewModel: viewModel,
                                preselectedGroup: editingGroup,
                                presentationStyle: .pushed
                            )
                            // onDisappear ИМЕННО на destination, не на NavigationLink/label (source):
                            // в NavigationStack onDisappear source-view срабатывает при push ВПЕРЁД
                            // (в момент тапа, до создания счёта), а на pop-back — нет. Destination же
                            // исчезает ровно при pop-back — единственный корректный момент рефреша
                            // (добавление core-счёта пуш-путём не публикует событий в EventBus, см.
                            // компаньон-фикс .hideAddAccountSheet у sheet-варианта). НЕ переносить на label.
                            .onDisappear {
                                viewModel.handle(.loadGroups)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            Text(L("finances.group.action.add_account"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    if !accounts.isEmpty || !coreAccounts.isEmpty {
                        FinancesRowDivider(leadingPadding: 0)
                            .padding(.horizontal, 16)
                    }

                    if accounts.isEmpty && coreAccounts.isEmpty {
                        Text(L("finances.main.empty_products.title"))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                    }

                    ForEach(accounts) { account in
                        if let accountInfo = viewModel.getAccountInfo(account: account) {
                            HStack(spacing: 12) {
                                // Иконка счета
                                Image(systemName: accountInfo.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.financesGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 24, height: 24)
                                
                                // Название и сумма счета
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(accountInfo.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                    
                                    HStack(spacing: 4) {
                                        Text(formatAmount(accountInfo.amount, isHidden: viewModel.state.isAmountHidden))
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(accountInfo.isCreditCardDebt ? AppColors.error : AppColors.textSecondary)
                                        
                                        Text(accountInfo.currency)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Кнопка удаления
                                Button {
                                    let info = viewModel.getAccountInfo(account: account)
                                    let amount = info?.amount ?? 0
                                    if abs(amount) > 0.001 {
                                        archiveBalanceWarningAmount = amount
                                        archiveBalanceWarningCurrency = info?.currency ?? ""
                                        pendingAccountDeletionAfterWarning = account
                                        showArchiveBalanceWarning = true
                                    } else {
                                        pendingAccountDeletion = account
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.error)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)

                            if account.id != accounts.last?.id || !coreAccounts.isEmpty {
                                FinancesRowDivider(leadingPadding: 52)
                            }
                        }
                    }

                    // [Ф5c.7 expand-contract, файл №2] core-счета группы — READ-ONLY в этом шаге
                    // (без кнопки удаления): `.removeAccountFromGroup(FinanceAccount)` легаси-типизирован
                    // (VM action-флип отложен на 5c.7.4+5c.7.5 по плану), а обходной прямой вызов
                    // `AccountsCoreService.archiveAccount` в обход VM-экшена завёл бы второй мутационный
                    // путь без баланс-warning'а, который есть у легаси-удаления — сознательно не тяну
                    // каскад ради этого шага (см. отчёт).
                    ForEach(coreAccounts, id: \.id) { account in
                        HStack(spacing: 12) {
                            NewCoreAccountRow(
                                account: account,
                                balance: viewModel.newCoreBalanceToday(account),
                                isAmountHidden: viewModel.state.isAmountHidden
                            )
                        }
                        .padding(.horizontal, 16)

                        if account.id != coreAccounts.last?.id {
                            FinancesRowDivider(leadingPadding: 52)
                        }
                    }
                }
            }
        }
    }

    private var managementSection: some View {
        Group {
            if let editingGroup = currentEditingGroup {
                VStack(alignment: .leading, spacing: 10) {
                    FinancesSectionHeader(title: L("finances.group_editor.section.manage"))
                    FinancesGlassCard {
                        VStack(spacing: 0) {
                            if presentationStyle.showsOpenCurrentGroupAction {
                                NavigationLink {
                                    FinanceDynamicsView(
                                        financeViewModel: viewModel,
                                        initialGroupID: editingGroup.groupUniqueID,
                                        initialGroupCurrency: editingGroup.displayCurrency,
                                        wrapInNavigationStack: false
                                    )
                                } label: {
                                    managementRow(
                                        title: L("finances.group.menu.open"),
                                        systemImage: "chart.line.uptrend.xyaxis",
                                        tint: AppColors.textPrimary
                                    )
                                }
                                .buttonStyle(.plain)

                                FinancesRowDivider(leadingPadding: 0)
                                    .padding(.horizontal, 16)
                            }

                            Button(role: .destructive) {
                                showDeleteGroupConfirmation = true
                            } label: {
                                managementRow(
                                    title: L("finances.common.delete"),
                                    systemImage: "trash",
                                    tint: AppColors.error
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveGroup() {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorHex = selectedColor.toHex()
        let normalizedIcon = selectedIconName.flatMap { $0.isEmpty ? nil : $0 }
        viewModel.handle(.updateGroup(
            name: normalizedName,
            colorHex: colorHex,
            displayCurrency: selectedCurrency,
            customIconName: normalizedIcon
        ))
        dismiss()
    }

    private func applyNameTemplate(_ template: FinanceGroupNameTemplate) {
        name = template.title
        isNameFocused = true
    }

    private var colorSectionTitle: String {
        let key = isColorPaletteExpanded
            ? "finances.group_editor.color.hide_palette"
            : "finances.group_editor.color.show_palette"
        return AppLocalization.string(key, locale: AppLocalization.currentAppLocale)
    }

    private func deleteGroup() {
        guard let editingGroup = currentEditingGroup else { return }
        viewModel.handle(.deleteGroup(editingGroup))
        dismiss()
    }

    private func confirmDeleteGroup() {
        showDeleteGroupConfirmation = false
        deleteGroup()
    }

    private func confirmDeleteAccount() {
        guard let account = pendingAccountDeletion else { return }
        pendingAccountDeletion = nil
        viewModel.removeLegacyAccountFromGroup(account)
    }

    private var deleteAccountConfirmationTitle: String {
        guard let account = pendingAccountDeletion else {
            return L("finances.dynamics.delete_account")
        }
        let name = viewModel.getAccountInfo(account: account)?.name
            ?? L("finances.dynamics.chart.account_fallback")
        return FinanceDeleteProductCopy.confirmationTitle(for: account.accountType, name: name)
    }

    private var deleteAccountConfirmationMessage: String {
        guard let account = pendingAccountDeletion else {
            return L("finances.dynamics.delete_account.confirm.message")
        }
        return String(localized: FinanceDeleteProductCopy.confirmationMessage(for: account.accountType))
    }

    private var deleteGroupConfirmationTitle: String {
        let groupName = currentEditingGroup?.name ?? L("finances.group.ungrouped")
        return FinancesL10n.format("finances.dynamics.delete_group.confirm.title_format", groupName)
    }

    private var deleteGroupConfirmationMessage: String {
        FinancesL10n.tr("finances.dynamics.delete_group.confirm.message")
    }

    private var archiveBalanceWarningMessage: String {
        let symbol = MonetaCurrency(rawValue: archiveBalanceWarningCurrency)?.symbol ?? archiveBalanceWarningCurrency
        let formatted = FinanceAmountText.withCurrency(
            value: abs(archiveBalanceWarningAmount),
            currencySymbol: symbol,
            isHidden: false
        )
        return FinancesL10n.format("finances.archive.balance_warning.message", formatted)
    }

    private func managementRow(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
    
    private func loadAvailableCurrencies() async {
        isLoadingCurrencies = true
        defer { isLoadingCurrencies = false }

        let currentCurrency = currentEditingGroup?.displayCurrency ?? SettingsManager.shared.primaryCurrencyCode
        availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: [currentCurrency])
    }
    
    private func formatAmount(_ amount: Double, isHidden: Bool = false) -> String {
        if isHidden {
            // Подсчитываем количество цифр в числе
            let digits = Int(amount.rounded())
            let digitCount = String(digits).count
            // Возвращаем точки вместо цифр
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}
