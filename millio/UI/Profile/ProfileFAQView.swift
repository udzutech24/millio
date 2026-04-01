//
//  ProfileFAQView.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import SwiftUI

struct ProfileFAQView: View {
    let selectedLanguage: Language

    private var locale: Locale {
        LocalizationSupport.resolvedLocale(for: selectedLanguage)
    }

    private var sections: [ProfileFAQSection] {
        ProfileFAQContent.sections(for: selectedLanguage)
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introBlock

                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(localized("profile.faq.title", locale: locale, fallback: "FAQ"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var introBlock: some View {
        return VStack(alignment: .leading, spacing: 8) {
            Text(localized("profile.faq.basic", locale: locale, fallback: "FAQ for getting started"))
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("profile.faq.subtitle", locale: locale, fallback: "Quick answers about how Millio works."))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .italic()
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.textSecondary.opacity(0.45))
                .frame(width: 3)
        }
    }

    private func sectionView(_ section: ProfileFAQSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(AppColors.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        ProfileFAQDetailView(item: item)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Circle()
                                .fill(AppColors.textSecondary.opacity(0.8))
                                .frame(width: 6, height: 6)

                            Text(item.question)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(AppColors.profileValueAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index != section.items.count - 1 {
                        Divider()
                            .overlay(AppColors.textPrimary.opacity(0.1))
                            .padding(.leading, 30)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.profileCardBackgroundGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.profileCardStrokeGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            )
        }
    }

    private func localized(_ key: String, locale: Locale, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}

struct ProfileFAQDetailView: View {
    let item: ProfileFAQItem
    private var questionPrefix: String {
        AppLocalization.string(
            "profile.faq.question_prefix",
            locale: AppLocalization.currentAppLocale,
            fallback: "Q:"
        )
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(questionPrefix) \(item.question)")
                        .font(.system(size: 36, weight: .medium, design: .serif))
                        .foregroundStyle(AppColors.textPrimary)

                    ForEach(item.answerParagraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineSpacing(4)
                    }

                    if let note = item.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .italic()
                            .padding(.leading, 16)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.textSecondary.opacity(0.45))
                                    .frame(width: 3)
                            }
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(
            AppLocalization.string("profile.faq.title", locale: AppLocalization.currentAppLocale, fallback: "FAQ")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        ProfileFAQView(selectedLanguage: .russian)
            .environment(AppState())
    }
}
