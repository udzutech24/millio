//
//  LanguageSelectionView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct LanguageSelectionView: View {
    @Binding var selectedLanguage: Language
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    private let availableLanguages: [Language]

    init(selectedLanguage: Binding<Language>, availableLanguages: [Language] = LocalizationSupport.userSelectableLanguages) {
        self._selectedLanguage = selectedLanguage
        self.availableLanguages = availableLanguages
    }

    private var currentLocale: Locale { AppLocalization.currentAppLocale }

    private func localized(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: currentLocale, fallback: fallback)
    }
    
    private var filteredLanguages: [Language] {
        if searchText.isEmpty {
            return availableLanguages
        }
        return availableLanguages.filter {
            $0.searchableNames(for: currentLocale)
                .contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 0) {
                InlineSearchBar(
                    text: $searchText,
                    placeholder: localized("profile.language.search_placeholder", fallback: "Search language")
                )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: localized("profile.language.all_languages", fallback: "All languages"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        
                        SelectionSectionCard {
                            ForEach(Array(filteredLanguages.enumerated()), id: \.element) { index, language in
                                SelectionItemRow(
                                    title: language.displayName(for: currentLocale),
                                    subtitle: nil,
                                    isSelected: selectedLanguage == language,
                                    dividerColor: AppColors.textPrimary.opacity(0.08),
                                    showDivider: index != filteredLanguages.count - 1,
                                    onTap: {
                                        selectedLanguage = language
                                        dismiss()
                                    },
                                    leading: {
                                        languageIcon(for: language)
                                    },
                                    trailing: {
                                        EmptyView()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle(localized("profile.language.navigation_title", fallback: "Language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func languageIcon(for language: Language) -> some View {
        let size: CGFloat = 24
        switch language {
        case .russian:
            Image("ru")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        case .english:
            Image("us")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        case .simplifiedChinese:
            Image(systemName: "globe.asia.australia.fill")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColors.textPrimary)
                .padding(5)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(AppColors.textPrimary.opacity(0.12))
                )
        case .german:
            Image("de")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        case .spanish:
            Image("es")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        case .system:
            Image(systemName: "globe")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColors.textPrimary)
                .padding(5)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(AppColors.textPrimary.opacity(0.12))
                )
        }
    }
}

#Preview {
    NavigationStack {
        LanguageSelectionView(selectedLanguage: .constant(.russian))
            .environment(AppState())
    }
}
