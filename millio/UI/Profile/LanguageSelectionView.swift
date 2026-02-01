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
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SelectionSectionCard {
                        ForEach(Array(Language.allCases.enumerated()), id: \.element) { index, language in
                            SelectionItemRow(
                                title: language.displayName,
                                subtitle: nil,
                                isSelected: selectedLanguage == language,
                                dividerColor: AppColors.textPrimary.opacity(0.08),
                                showDivider: index != Language.allCases.count - 1,
                                onTap: {
                                    selectedLanguage = language
                                    dismiss()
                                },
                                leading: {
                                    Image(systemName: "globe")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(AppColors.textPrimary)
                                },
                                trailing: {
                                    EmptyView()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Язык")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LanguageSelectionView(selectedLanguage: .constant(.russian))
    }
}
