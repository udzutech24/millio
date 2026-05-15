//
//  CashflowCategoryQuickCreateSheet.swift
//  millio
//

import SwiftUI

private func cashflowEditorSheetText(_ key: String, fallback: String? = nil) -> String {
    AppLocalization.string(key, locale: AppLocalization.currentAppLocale, fallback: fallback)
}

struct CashflowCategoryQuickCreateSheet: View {
    private enum IconPickerTab: String, CaseIterable, Identifiable {
        case emoji = "Emoji"
        case symbols = "Icons"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .emoji:
                return cashflowEditorSheetText("cashflow.editor.icon_tab.emoji")
            case .symbols:
                return cashflowEditorSheetText("cashflow.editor.icon_tab.symbols")
            }
        }
    }

    @Binding var name: String
    @Binding var icon: String
    let kind: CashflowCategoryKind
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var selectedTab: IconPickerTab = .emoji
    @State private var iconSearchText: String = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredSymbolIcons: [String] {
        let query = iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return CashflowCustomCategory.allowedSFSymbolIcons }
        return CashflowCustomCategory.allowedSFSymbolIcons.filter { $0.lowercased().contains(query) }
    }

    private var visibleIcons: [String] {
        switch selectedTab {
        case .emoji:
            return kind == .income
                ? CashflowCustomCategory.allowedEmojiIconsIncome
                : CashflowCustomCategory.allowedEmojiIcons
        case .symbols:
            return filteredSymbolIcons
        }
    }

    private var suggestedIcons: [String] {
        kind == .income
            ? CashflowCategoryIconSuggestionEngine.suggestedIcons(forIncomeName: name)
            : CashflowCategoryIconSuggestionEngine.suggestedIcons(forExpenseName: name)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        FinancesSectionHeader(title: cashflowEditorSheetText("cashflow.editor.category_name"))
                        FinancesGlassCard {
                            TextField(cashflowEditorSheetText("cashflow.editor.enter_name"), text: $name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($isNameFieldFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }

                        FinancesSectionHeader(title: cashflowEditorSheetText("cashflow.editor.category_icon"))
                        FinancesGlassCard {
                            VStack(spacing: 12) {
                                if !suggestedIcons.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(cashflowEditorSheetText("cashflow.editor.icon_suggestions", fallback: "Suggested icons"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 10) {
                                                ForEach(suggestedIcons, id: \.self) { suggested in
                                                    Button {
                                                        icon = suggested
                                                    } label: {
                                                        CashflowCategoryIconView(
                                                            icon: suggested,
                                                            fontSize: 22,
                                                            fontWeight: .semibold,
                                                            tint: AnyShapeStyle(icon == suggested ? AppColors.textPrimary : AppColors.textSecondary)
                                                        )
                                                        .frame(width: 52, height: 52)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                .fill(icon == suggested ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                        .stroke(Color.white.opacity(icon == suggested ? 0.24 : 0.10), lineWidth: 1)
                                                                )
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.horizontal, 2)
                                        }
                                    }
                                }

                                Picker(cashflowEditorSheetText("cashflow.editor.icon_type"), selection: $selectedTab) {
                                    ForEach(IconPickerTab.allCases) { tab in
                                        Text(tab.localizedTitle).tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if selectedTab == .symbols {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppColors.textTertiary)
                                        TextField(cashflowEditorSheetText("cashflow.editor.icon_search_hint"), text: $iconSearchText)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(AppColors.textPrimary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                                    ForEach(visibleIcons, id: \.self) { symbol in
                                    Button {
                                        icon = symbol
                                    } label: {
                                        CashflowCategoryIconView(
                                            icon: symbol,
                                            fontSize: 22,
                                            fontWeight: .semibold,
                                            tint: AnyShapeStyle(icon == symbol ? AppColors.textPrimary : AppColors.textSecondary)
                                        )
                                            .frame(width: 54, height: 54)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(icon == symbol ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                            .stroke(Color.white.opacity(icon == symbol ? 0.24 : 0.10), lineWidth: 1)
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            }
                            .padding(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle(L("cashflow.editor.new_category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    }
                    .accessibilityLabel(L("cashflow.common.cancel"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(name, icon)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(canSave ? Color(hex: "6DFFC7") : AppColors.textSecondary.opacity(0.55))
                    }
                    .accessibilityLabel(L("cashflow.common.save"))
                    .disabled(!canSave)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    isNameFieldFocused = true
                }
                selectedTab = CashflowCustomCategory.isSFSymbolIcon(icon) ? .symbols : .emoji
                iconSearchText = ""
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
