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
    
    private var filteredLanguages: [Language] {
        let all = Language.allCases
        if searchText.isEmpty {
            return all
        }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 0) {
                InlineSearchBar(text: $searchText, placeholder: "Поиск языка")
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Все языки")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        
                        SelectionSectionCard {
                            ForEach(Array(filteredLanguages.enumerated()), id: \.element) { index, language in
                                SelectionItemRow(
                                    title: language.displayName,
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
        .navigationTitle("Язык")
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
    }
}
