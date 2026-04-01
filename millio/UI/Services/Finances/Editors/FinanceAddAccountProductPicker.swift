//
//  FinanceAddAccountProductPicker.swift
//  millio
//
//  Централизует сценарии выбора продукта перед открытием полной формы,
//  чтобы initial add-flow и последующее переключение типа опирались на одну модель.
//

import SwiftUI

private func financeAddAccountCopy(_ key: String, locale: Locale) -> String {
    FinancesL10n.tr(key, locale: locale)
}

struct FinanceAddAccountProductSelection: Equatable {
    let accountType: FinanceAccountType
    let investmentCategory: InvestmentCategory
    let investmentPreset: FinanceAddAccountInvestmentPreset
    let title: String
}

struct FinanceAddAccountGroupRecommendation: Equatable, Identifiable {
    let titleKey: String
    let subtitleKey: String
    let iconName: String
    let accentHex: String

    var id: String { "\(titleKey)|\(subtitleKey)|\(iconName)" }

    func title(locale: Locale) -> String {
        financeAddAccountCopy(titleKey, locale: locale)
    }

    func subtitle(locale: Locale) -> String {
        financeAddAccountCopy(subtitleKey, locale: locale)
    }
}

enum FinanceAddAccountProductSection: String, CaseIterable, Identifiable {
    case money
    case liabilities
    case assets

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .money:
            return financeAddAccountCopy("finances.add_account.product.section.money.title", locale: locale)
        case .liabilities:
            return financeAddAccountCopy("finances.add_account.product.section.liabilities.title", locale: locale)
        case .assets:
            return financeAddAccountCopy("finances.add_account.product.section.assets.title", locale: locale)
        }
    }

    func subtitle(locale: Locale) -> String {
        switch self {
        case .money:
            return financeAddAccountCopy("finances.add_account.product.section.money.subtitle", locale: locale)
        case .liabilities:
            return financeAddAccountCopy("finances.add_account.product.section.liabilities.subtitle", locale: locale)
        case .assets:
            return financeAddAccountCopy("finances.add_account.product.section.assets.subtitle", locale: locale)
        }
    }
}

struct FinanceAddAccountProductSectionModel: Identifiable, Equatable {
    let section: FinanceAddAccountProductSection
    let options: [FinanceAddAccountProductOption]

    var id: FinanceAddAccountProductSection { section }
}

enum FinanceAddAccountProductOption: String, CaseIterable, Identifiable {
    case card
    case account
    case deposit
    case credit
    case investment
    case house
    case stocks
    case business
    case debt
    case crypto
    case other

    var id: String { rawValue }

    var section: FinanceAddAccountProductSection {
        switch self {
        case .card, .account, .deposit:
            return .money
        case .credit, .debt:
            return .liabilities
        case .investment, .house, .stocks, .business, .crypto, .other:
            return .assets
        }
    }

    var iconName: String {
        switch self {
        case .card:
            return FinanceAccountType.card.icon
        case .account:
            return "building.columns.fill"
        case .deposit:
            return "building.columns.circle.fill"
        case .credit:
            return FinanceAccountType.credit.icon
        case .investment:
            return FinanceAccountType.investment.icon
        case .house:
            return InvestmentCategory.house.icon
        case .stocks:
            return InvestmentCategory.stocks.icon
        case .business:
            return InvestmentCategory.business.icon
        case .debt:
            return InvestmentCategory.debt.icon
        case .crypto:
            return InvestmentCategory.crypto.icon
        case .other:
            return InvestmentCategory.other.icon
        }
    }

    var title: String {
        title(locale: AppLocalization.currentAppLocale)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .card:
            return financeAddAccountCopy("finances.add_account.product.card.title", locale: locale)
        case .account:
            return financeAddAccountCopy("finances.add_account.product.account.title", locale: locale)
        case .deposit:
            return financeAddAccountCopy("finances.add_account.product.deposit.title", locale: locale)
        case .credit:
            return financeAddAccountCopy("finances.add_account.product.credit.title", locale: locale)
        case .investment:
            return financeAddAccountCopy("finances.add_account.product.investment.title", locale: locale)
        case .house:
            return financeAddAccountCopy("finances.add_account.product.house.title", locale: locale)
        case .stocks:
            return financeAddAccountCopy("finances.add_account.product.stocks.title", locale: locale)
        case .business:
            return financeAddAccountCopy("finances.add_account.product.business.title", locale: locale)
        case .debt:
            return financeAddAccountCopy("finances.add_account.product.debt.title", locale: locale)
        case .crypto:
            return financeAddAccountCopy("finances.add_account.product.crypto.title", locale: locale)
        case .other:
            return financeAddAccountCopy("finances.add_account.product.other.title", locale: locale)
        }
    }

    func subtitle(locale: Locale) -> String {
        switch self {
        case .card:
            return financeAddAccountCopy("finances.add_account.product.card.subtitle", locale: locale)
        case .account:
            return financeAddAccountCopy("finances.add_account.product.account.subtitle", locale: locale)
        case .deposit:
            return financeAddAccountCopy("finances.add_account.product.deposit.subtitle", locale: locale)
        case .credit:
            return financeAddAccountCopy("finances.add_account.product.credit.subtitle", locale: locale)
        case .investment:
            return financeAddAccountCopy("finances.add_account.product.investment.subtitle", locale: locale)
        case .house:
            return financeAddAccountCopy("finances.add_account.product.house.subtitle", locale: locale)
        case .stocks:
            return financeAddAccountCopy("finances.add_account.product.stocks.subtitle", locale: locale)
        case .business:
            return financeAddAccountCopy("finances.add_account.product.business.subtitle", locale: locale)
        case .debt:
            return financeAddAccountCopy("finances.add_account.product.debt.subtitle", locale: locale)
        case .crypto:
            return financeAddAccountCopy("finances.add_account.product.crypto.subtitle", locale: locale)
        case .other:
            return financeAddAccountCopy("finances.add_account.product.other.subtitle", locale: locale)
        }
    }

    var selection: FinanceAddAccountProductSelection {
        selection(locale: AppLocalization.currentAppLocale)
    }

    func selection(locale: Locale) -> FinanceAddAccountProductSelection {
        switch self {
        case .card:
            return FinanceAddAccountProductSelection(
                accountType: .card,
                investmentCategory: .other,
                investmentPreset: .asset,
                title: title(locale: locale)
            )
        case .account:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .other,
                investmentPreset: .account,
                title: title(locale: locale)
            )
        case .deposit:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .other,
                investmentPreset: .deposit,
                title: title(locale: locale)
            )
        case .credit:
            return FinanceAddAccountProductSelection(
                accountType: .credit,
                investmentCategory: .other,
                investmentPreset: .asset,
                title: title(locale: locale)
            )
        case .investment:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .other,
                investmentPreset: .asset,
                title: title(locale: locale)
            )
        case .house:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .house,
                investmentPreset: .category,
                title: title(locale: locale)
            )
        case .stocks:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .stocks,
                investmentPreset: .category,
                title: title(locale: locale)
            )
        case .business:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .business,
                investmentPreset: .category,
                title: title(locale: locale)
            )
        case .debt:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .debt,
                investmentPreset: .category,
                title: title(locale: locale)
            )
        case .crypto:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .crypto,
                investmentPreset: .category,
                title: title(locale: locale)
            )
        case .other:
            return FinanceAddAccountProductSelection(
                accountType: .investment,
                investmentCategory: .other,
                investmentPreset: .category,
                title: title(locale: locale)
            )
        }
    }

    var groupRecommendations: [FinanceAddAccountGroupRecommendation] {
        switch self {
        case .card:
            return [
                .init(titleKey: "finances.add_account.product.card.recommendation.1.title", subtitleKey: "finances.add_account.product.card.recommendation.1.subtitle", iconName: "wallet.pass.fill", accentHex: "3B82F6"),
                .init(titleKey: "finances.add_account.product.card.recommendation.2.title", subtitleKey: "finances.add_account.product.card.recommendation.2.subtitle", iconName: "creditcard.fill", accentHex: "2563EB")
            ]
        case .account:
            return [
                .init(titleKey: "finances.add_account.product.account.recommendation.1.title", subtitleKey: "finances.add_account.product.account.recommendation.1.subtitle", iconName: "building.columns.fill", accentHex: "60A5FA"),
                .init(titleKey: "finances.add_account.product.account.recommendation.2.title", subtitleKey: "finances.add_account.product.account.recommendation.2.subtitle", iconName: "lifepreserver.fill", accentHex: "38BDF8")
            ]
        case .deposit:
            return [
                .init(titleKey: "finances.add_account.product.deposit.recommendation.1.title", subtitleKey: "finances.add_account.product.deposit.recommendation.1.subtitle", iconName: "building.columns.circle.fill", accentHex: "38BDF8"),
                .init(titleKey: "finances.add_account.product.deposit.recommendation.2.title", subtitleKey: "finances.add_account.product.deposit.recommendation.2.subtitle", iconName: "lock.shield.fill", accentHex: "0EA5E9")
            ]
        case .credit:
            return [
                .init(titleKey: "finances.add_account.product.credit.recommendation.1.title", subtitleKey: "finances.add_account.product.credit.recommendation.1.subtitle", iconName: "creditcard.trianglebadge.exclamationmark", accentHex: "F59E0B"),
                .init(titleKey: "finances.add_account.product.credit.recommendation.2.title", subtitleKey: "finances.add_account.product.credit.recommendation.2.subtitle", iconName: "calendar.badge.clock", accentHex: "D97706")
            ]
        case .investment:
            return [
                .init(titleKey: "finances.add_account.product.investment.recommendation.1.title", subtitleKey: "finances.add_account.product.investment.recommendation.1.subtitle", iconName: "chart.line.uptrend.xyaxis", accentHex: "2DD4BF"),
                .init(titleKey: "finances.add_account.product.investment.recommendation.2.title", subtitleKey: "finances.add_account.product.investment.recommendation.2.subtitle", iconName: "hourglass.bottomhalf.filled", accentHex: "14B8A6")
            ]
        case .house:
            return [
                .init(titleKey: "finances.add_account.product.house.recommendation.1.title", subtitleKey: "finances.add_account.product.house.recommendation.1.subtitle", iconName: "house.fill", accentHex: "34D399"),
                .init(titleKey: "finances.add_account.product.house.recommendation.2.title", subtitleKey: "finances.add_account.product.house.recommendation.2.subtitle", iconName: "building.2.fill", accentHex: "10B981")
            ]
        case .stocks:
            return [
                .init(titleKey: "finances.add_account.product.stocks.recommendation.1.title", subtitleKey: "finances.add_account.product.stocks.recommendation.1.subtitle", iconName: "chart.bar.fill", accentHex: "22C55E"),
                .init(titleKey: "finances.add_account.product.stocks.recommendation.2.title", subtitleKey: "finances.add_account.product.stocks.recommendation.2.subtitle", iconName: "building.columns.circle.fill", accentHex: "16A34A")
            ]
        case .business:
            return [
                .init(titleKey: "finances.add_account.product.business.recommendation.1.title", subtitleKey: "finances.add_account.product.business.recommendation.1.subtitle", iconName: "briefcase.fill", accentHex: "A78BFA"),
                .init(titleKey: "finances.add_account.product.business.recommendation.2.title", subtitleKey: "finances.add_account.product.business.recommendation.2.subtitle", iconName: "folder.fill", accentHex: "8B5CF6")
            ]
        case .debt:
            return [
                .init(titleKey: "finances.add_account.product.debt.recommendation.1.title", subtitleKey: "finances.add_account.product.debt.recommendation.1.subtitle", iconName: "arrow.uturn.left.circle.fill", accentHex: "FB7185"),
                .init(titleKey: "finances.add_account.product.debt.recommendation.2.title", subtitleKey: "finances.add_account.product.debt.recommendation.2.subtitle", iconName: "hand.thumbsup.fill", accentHex: "F43F5E")
            ]
        case .crypto:
            return [
                .init(titleKey: "finances.add_account.product.crypto.recommendation.1.title", subtitleKey: "finances.add_account.product.crypto.recommendation.1.subtitle", iconName: "bitcoinsign.circle.fill", accentHex: "F59E0B"),
                .init(titleKey: "finances.add_account.product.crypto.recommendation.2.title", subtitleKey: "finances.add_account.product.crypto.recommendation.2.subtitle", iconName: "wallet.pass.fill", accentHex: "D97706")
            ]
        case .other:
            return [
                .init(titleKey: "finances.add_account.product.other.recommendation.1.title", subtitleKey: "finances.add_account.product.other.recommendation.1.subtitle", iconName: "shippingbox.fill", accentHex: "38BDF8"),
                .init(titleKey: "finances.add_account.product.other.recommendation.2.title", subtitleKey: "finances.add_account.product.other.recommendation.2.subtitle", iconName: "square.stack.3d.up.fill", accentHex: "0EA5E9")
            ]
        }
    }

    static var visibleOptions: [FinanceAddAccountProductOption] {
        [.card, .account, .deposit, .credit, .debt, .investment, .house, .stocks, .business, .crypto]
    }

    static var visibleSections: [FinanceAddAccountProductSectionModel] {
        FinanceAddAccountProductSection.allCases.compactMap { section in
            let options = visibleOptions.filter { $0.section == section }
            guard !options.isEmpty else { return nil }
            return FinanceAddAccountProductSectionModel(section: section, options: options)
        }
    }

    static func currentSelection(
        accountType: FinanceAccountType,
        investmentCategory: InvestmentCategory,
        investmentPreset: FinanceAddAccountInvestmentPreset
    ) -> FinanceAddAccountProductOption {
        switch accountType {
        case .card:
            return .card
        case .credit:
            return .credit
        case .investment:
            if investmentCategory == .other, investmentPreset == .account {
                return .account
            }
            if investmentCategory == .other, investmentPreset == .deposit {
                return .deposit
            }

            switch investmentCategory {
            case .house:
                return .house
            case .stocks:
                return .stocks
            case .business:
                return .business
            case .debt:
                return .debt
            case .crypto:
                return .crypto
            case .other, .car, .bonds, .metals:
                return .investment
            }
        }
    }
}

enum FinanceAddAccountPresentationPolicy {
    static func shouldAutoPresentTypePicker(
        isEditingMode: Bool,
        preselectedAccountType: FinanceAccountType?
    ) -> Bool {
        !isEditingMode && preselectedAccountType == nil
    }
}

struct FinanceAddAccountProductPickerSheet: View {
    let availableSize: CGSize
    let onClose: () -> Void
    let onSelect: (FinanceAddAccountProductOption) -> Void

    @Environment(\.locale) private var locale
    @State private var animateContent = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        let layout = FinanceAddAccountProductGridLayout(availableSize: availableSize)

        FinancesGlassCard(
            accentColor: FinanceScreenChrome.accentColor,
            cornerRadius: FinanceScreenChrome.actionSheetCornerRadius,
            contentPadding: EdgeInsets(top: layout.topPadding, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(spacing: layout.containerSpacing) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 38, height: 5)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 8)
                    .animation(.easeOut(duration: 0.24), value: animateContent)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(financeAddAccountCopy("finances.add_account.product_picker.title", locale: locale))
                            .font(.system(size: layout.titleFontSize, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(financeAddAccountCopy("finances.add_account.product_picker.subtitle", locale: locale))
                            .font(.system(size: layout.subtitleFontSize, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                            .frame(width: layout.closeButtonSide, height: layout.closeButtonSide)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(financeAddAccountCopy("finances.common.close", locale: locale))
                }
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)
                .animation(.spring(response: 0.42, dampingFraction: 0.88), value: animateContent)

                LazyVGrid(columns: columns, spacing: layout.gridSpacing) {
                    ForEach(Array(FinanceAddAccountProductOption.visibleOptions.enumerated()), id: \.element.id) { index, option in
                        optionTile(for: option, layout: layout, index: index)
                    }
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(height: layout.sheetHeight, alignment: .top)
        }
        .onAppear {
            animateContent = false
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                animateContent = true
            }
        }
    }

    private func optionTile(
        for option: FinanceAddAccountProductOption,
        layout: FinanceAddAccountProductGridLayout,
        index: Int
    ) -> some View {
        let accent = iconAccentColor(for: option)

        return Button {
            onSelect(option)
        } label: {
            VStack(alignment: .leading, spacing: layout.tileContentSpacing) {
                HStack {
                    Spacer(minLength: 0)
                    Image(systemName: option.iconName)
                        .font(.system(size: layout.iconSize, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: layout.iconBadgeSide, height: layout.iconBadgeSide)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(accent.opacity(0.12))
                        )
                }
                .padding(.bottom, layout.topRowBottomSpacing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title(locale: locale))
                        .font(.system(size: layout.titleTileFontSize, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                        .lineSpacing(1)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, minHeight: layout.titleBlockHeight, alignment: .topLeading)

                    Text(compactSubtitle(for: option))
                        .font(.system(size: layout.tileSubtitleFontSize, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                        .frame(maxWidth: .infinity, minHeight: layout.subtitleBlockHeight, alignment: .topLeading)
                }
                .frame(minHeight: layout.textBlockMinHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, layout.textBlockTopOffset)
                .padding(.bottom, layout.textBottomInset)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.tileHorizontalPadding)
            .padding(.vertical, layout.tileVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: layout.tileHeight, maxHeight: layout.tileHeight, alignment: .topLeading)
            .background(tileBackground)
            .scaleEffect(animateContent ? 1 : 0.96)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 18)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.86)
                    .delay(Double(index) * 0.024),
                value: animateContent
            )
        }
        .buttonStyle(.plain)
    }

    private func iconAccentColor(for option: FinanceAddAccountProductOption) -> Color {
        switch option {
        case .card:
            return Color(hex: "3B82F6")
        case .account:
            return Color(hex: "60A5FA")
        case .deposit:
            return Color(hex: "38BDF8")
        case .credit:
            return Color(hex: "F59E0B")
        case .investment:
            return Color(hex: "2DD4BF")
        case .house:
            return Color(hex: "34D399")
        case .stocks:
            return Color(hex: "22C55E")
        case .business:
            return Color(hex: "A78BFA")
        case .debt:
            return Color(hex: "FB7185")
        case .crypto:
            return Color(hex: "F59E0B")
        case .other:
            return Color(hex: "38BDF8")
        }
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.055),
                        Color.white.opacity(0.028)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func compactSubtitle(for option: FinanceAddAccountProductOption) -> String {
        switch option {
        case .card:
            return financeAddAccountCopy("finances.add_account.product.card.compact_subtitle", locale: locale)
        case .account:
            return financeAddAccountCopy("finances.add_account.product.account.compact_subtitle", locale: locale)
        case .deposit:
            return financeAddAccountCopy("finances.add_account.product.deposit.compact_subtitle", locale: locale)
        case .credit:
            return financeAddAccountCopy("finances.add_account.product.credit.compact_subtitle", locale: locale)
        case .investment:
            return financeAddAccountCopy("finances.add_account.product.investment.compact_subtitle", locale: locale)
        case .house:
            return financeAddAccountCopy("finances.add_account.product.house.compact_subtitle", locale: locale)
        case .stocks:
            return financeAddAccountCopy("finances.add_account.product.stocks.compact_subtitle", locale: locale)
        case .business:
            return financeAddAccountCopy("finances.add_account.product.business.compact_subtitle", locale: locale)
        case .debt:
            return financeAddAccountCopy("finances.add_account.product.debt.compact_subtitle", locale: locale)
        case .crypto:
            return financeAddAccountCopy("finances.add_account.product.crypto.compact_subtitle", locale: locale)
        case .other:
            return financeAddAccountCopy("finances.add_account.product.other.compact_subtitle", locale: locale)
        }
    }
}

private struct FinanceAddAccountProductGridLayout {
    let availableSize: CGSize

    private var safeWidth: CGFloat {
        let width = availableSize.width
        guard width.isFinite, width > 0 else { return 375 }
        return width
    }

    private var safeHeight: CGFloat {
        let height = availableSize.height
        guard height.isFinite, height > 0 else { return 812 }
        return height
    }

    private var compactHeight: Bool { safeHeight < 760 }

    var sheetHeight: CGFloat {
        let candidate = min(safeHeight - (compactHeight ? 70 : 96), compactHeight ? 640 : 730)
        return max(compactHeight ? 590 : 650, candidate)
    }

    var topPadding: CGFloat {
        compactHeight ? 12 : 16
    }

    var containerSpacing: CGFloat {
        compactHeight ? 8 : 12
    }

    var gridSpacing: CGFloat {
        compactHeight ? 8 : 10
    }

    var titleFontSize: CGFloat {
        compactHeight ? 21 : 24
    }

    var subtitleFontSize: CGFloat {
        compactHeight ? 11 : 12
    }

    var closeButtonSide: CGFloat {
        compactHeight ? 32 : 34
    }

    var tileHeight: CGFloat {
        let rowCount = max(1.0, ceil(Double(FinanceAddAccountProductOption.visibleOptions.count) / 2.0))
        let reservedHeight = compactHeight ? 106.0 : 122.0
        let verticalSpacing = gridSpacing * max(0, rowCount - 1)
        let rawHeight = (sheetHeight - reservedHeight - verticalSpacing) / rowCount
        let clamped = min(compactHeight ? 95 : 104, rawHeight)
        return max(compactHeight ? 82 : 90, clamped.isFinite ? clamped : (compactHeight ? 88 : 96))
    }

    var tileHorizontalPadding: CGFloat {
        compactHeight ? 12 : 14
    }

    var tileVerticalPadding: CGFloat {
        compactHeight ? 9 : 10
    }

    var tileContentSpacing: CGFloat {
        compactHeight ? 5 : 7
    }

    var topRowBottomSpacing: CGFloat {
        compactHeight ? 2 : 4
    }

    var iconSize: CGFloat {
        compactHeight ? 14 : 15
    }

    var iconBadgeSide: CGFloat {
        safeWidth < 380 ? 28 : 30
    }

    var titleTileFontSize: CGFloat {
        safeWidth < 380 ? 14 : (compactHeight ? 15 : 16)
    }

    var tileSubtitleFontSize: CGFloat {
        safeWidth < 380 ? 10 : (compactHeight ? 11 : 12)
    }

    var textBlockMinHeight: CGFloat {
        compactHeight ? 48 : 54
    }

    var titleBlockHeight: CGFloat {
        compactHeight ? 20 : 22
    }

    var subtitleBlockHeight: CGFloat {
        compactHeight ? 28 : 30
    }

    var textBlockTopOffset: CGFloat {
        compactHeight ? -2 : -2
    }

    var textBottomInset: CGFloat {
        compactHeight ? 5 : 6
    }
}
