import SwiftUI
import SwiftData
import PhotosUI

/// Секции формы создания счёта: имя, тип продукта, группа, начинка по типу и подсказки валидации.
extension FinanceAddAccountView {
    // MARK: - Form Sections
    
    var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.add_account.section.name"))
            FinancesGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button { showIconPicker = true } label: {
                            AccountIconBadgeView(
                                iconName: draftIconName,
                                iconColor: draftIconColor,
                                fallback: iconForSelectedType,
                                size: 32
                            )
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showIconPicker) {
                            AccountIconPickerSheet(
                                iconName: $draftIconName,
                                iconColor: $draftIconColor
                            )
                        }

                        TextField(placeholderForSelectedType, text: $accountName)
                            .foregroundStyle(AppColors.textPrimary)
                            .focused($isNameFieldFocused)
                            .textInputAutocapitalization(selectedAccountType == .card ? .words : .sentences)
                            .submitLabel(.done)
                            .disabled(isTickerDrivenName)
                            .opacity(isTickerDrivenName ? 0.75 : 1.0)
                    }
                    
                    if isTickerDrivenName {
                        Text(L("finances.add_account.name.autofill_hint"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                            .padding(.leading, 34)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }
    
    var iconForSelectedType: String {
        switch selectedAccountType {
        case .card: return "creditcard"
        case .credit: return "doc.text"
        case .investment: return "chart.pie.fill"
        }
    }
    
    var placeholderForSelectedType: String {
        switch selectedAccountType {
        case .card:
            return L("finances.add_account.placeholder.card")
        case .credit:
            return L("finances.add_account.placeholder.credit")
        case .investment:
            if isTickerDrivenName {
                return L("finances.add_account.placeholder.market")
            }
            if selectedInvestmentCategory == .other, selectedInvestmentPreset == .account {
                return L("finances.add_account.placeholder.account")
            }
            switch selectedInvestmentCategory {
            case .house:
                return L("finances.add_account.placeholder.investment.house")
            case .stocks:
                return L("finances.add_account.placeholder.investment.stocks")
            case .business:
                return L("finances.add_account.placeholder.investment.business")
            case .debt:
                return L("finances.add_account.placeholder.investment.debt")
            case .crypto:
                return L("finances.add_account.placeholder.investment.crypto")
            case .car:
                return L("finances.add_account.placeholder.investment.car")
            case .bonds:
                return L("finances.add_account.placeholder.investment.bonds")
            case .metals:
                return L("finances.add_account.placeholder.investment.metals")
            case .other:
                return L("finances.add_account.placeholder.investment.other")
            }
        }
    }

    var isTickerDrivenName: Bool {
        selectedAccountType == .investment && (selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto)
    }
    
    var accountTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.add_account.section.type"))
            FinancesGlassCard {
                Button {
                    showProductPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Text(L("finances.add_account.product.type"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        Text(selectedProductTypeTitle)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var visibleInvestmentCategories: [InvestmentCategory] {
        [.house, .stocks, .business, .debt, .crypto, .other]
    }

    var selectedProductOption: FinanceAddAccountProductOption {
        FinanceAddAccountProductOption.currentSelection(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            investmentPreset: selectedInvestmentPreset
        )
    }

    var groupRecommendations: [FinanceAddAccountGroupRecommendation] {
        guard hasConfirmedProductSelection else { return [] }
        return Array(selectedProductOption.groupRecommendations.prefix(2))
    }
    
    var groupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.add_account.section.group"))
            
            if viewModel.state.groups.isEmpty {
                FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                    VStack(spacing: 12) {
                        Text(L("finances.add_account.group.default_hint"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Button {
                            presentCreateGroup()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                Text(L("finances.add_account.group.create"))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                }
            } else {
                let currentGroupID = resolvedGroup?.groupUniqueID
                let currentGroupName = resolvedGroup?.name ?? L("finances.group.ungrouped")
                let selectableGroups = viewModel.state.groups.filter { $0.name != L("finances.group.ungrouped") }
                
                FinancesGlassCard {
                    Menu {
                        Button {
                            selectedGroupID = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(width: 12, height: 12)

                                Text(L("finances.group.ungrouped"))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)

                                Spacer()

                                if currentGroupID == nil {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.financesGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                        }

                        ForEach(selectableGroups) { group in
                            Button {
                                selectedGroupID = group.groupUniqueID
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(group.color)
                                        .frame(width: 12, height: 12)
                                    
                                    Text(group.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    Spacer()
                                    
                                    if currentGroupID == group.groupUniqueID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.financesGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(L("finances.add_account.section.group"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            
                            Spacer()
                            
                            Text(currentGroupName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                }
                
                Button {
                    presentCreateGroup()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                        Text(L("finances.add_account.group.create_new"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
                .padding(.top, 4)

                if !groupRecommendations.isEmpty {
                    recommendedGroupsSection
                }
            }
        }
    }

    var recommendedGroupsSection: some View {
        HStack(spacing: 10) {
            ForEach(groupRecommendations) { recommendation in
                recommendedGroupButton(recommendation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func recommendedGroupButton(_ recommendation: FinanceAddAccountGroupRecommendation) -> some View {
        let isSelected = resolvedGroup?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(recommendation.title(locale: locale)) == .orderedSame

        return Button {
            applyGroupRecommendation(recommendation)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recommendation.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: recommendation.accentHex))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: recommendation.accentHex).opacity(0.14))
                    )

                Text(recommendation.title(locale: locale))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: recommendation.accentHex))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.085 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color(hex: recommendation.accentHex).opacity(isSelected ? 0.38 : 0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    func presentCreateGroup() {
        groupIDsBeforeCreate = Set(viewModel.state.groups.map(\.groupUniqueID))
        showCreateGroup = true
    }

    func applyGroupRecommendation(_ recommendation: FinanceAddAccountGroupRecommendation) {
        let suggestedName = recommendation.title(locale: locale).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestedName.isEmpty else { return }

        if let existingGroup = viewModel.state.groups.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
        }) {
            selectedGroupID = existingGroup.groupUniqueID
            return
        }

        let maxOrder = viewModel.state.groups.map(\.order).max() ?? -1
        let newGroup = AccountGroup(name: suggestedName, colorHex: recommendation.accentHex, order: maxOrder + 1)
        viewModel.modelContext.insert(newGroup)

        do {
            try viewModel.modelContext.save()
            viewModel.handle(.loadGroups)
            selectedGroupID = newGroup.groupUniqueID
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to create recommended group: \(error.localizedDescription)")
        }
    }
    
    @ViewBuilder
    var createFormSections: some View {
        switch selectedAccountType {
        case .card:
            InlineCardCreateForm(
                name: $accountName,
                allowsTypeSwitching: true,
                selectedProductTitle: selectedProductTypeTitle,
                onOpenProductPicker: {
                    showProductPicker = true
                },
                onCardDataChanged: { card in
                    self.cardData = card
                    if card.cardType != .debit {
                        invalidateStatementDraft()
                    }
                }
            ) {
                groupSection
            }
        case .credit:
            InlineCreditCreateForm(
                name: $accountName,
                onCreditDataChanged: { data in
                    self.creditData = data
                },
                onLoanTermsChanged: { draft in
                    self.loanTermsDraft = draft
                }
            ) {
                groupSection
            }
        case .investment:
            if selectedInvestmentPreset == .deposit {
                // Вклад/накопительный счёт — новое ядро event-sourcing (Фаза 3), НЕ старый Investment(isDeposit:).
                InlineDepositCreateForm(
                    name: $accountName,
                    onDepositDataChanged: { data in self.depositData = data }
                ) {
                    groupSection
                }
            } else {
                InlineInvestmentCreateForm(
                    name: $accountName,
                    selectedCategory: $selectedInvestmentCategory,
                    onInvestmentDataChanged: { data in
                        self.investmentData = data
                    }
                ) {
                    groupSection
                }
            }
        }
    }

    @ViewBuilder
    var validationHintsSection: some View {
        if !validationHints.isEmpty, !areHintsHidden {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    FinancesSectionHeader(title: L("finances.add_account.section.hints"))
                    Spacer()
                    Button {
                        areHintsHidden = true
                        UserDefaults.standard.set(true, forKey: HintsPrefs.hiddenKey)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("finances.add_account.hints.hide"))
                }
                FinancesGlassCard(accentColor: warningAccentColor, contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(validationHints) { hint in
                            HStack(spacing: 8) {
                                Image(systemName: hint.kind == .required ? "exclamationmark.triangle.fill" : "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(hint.kind == .required ? warningAccentColor : recommendationAccentColor)
                                    .frame(width: 14)
                                Text(hint.text)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.28))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                (hint.kind == .required ? warningAccentColor : recommendationAccentColor).opacity(0.65),
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                    }
                }
            }
        }
    }
}
