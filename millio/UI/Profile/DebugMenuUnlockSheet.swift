//
//  DebugMenuUnlockSheet.swift
//  millio
//
//  Created by Codex on 09.03.2026.
//

import SwiftUI

/// Password gate for enabling the hidden Profile "Debug" section.
struct DebugMenuUnlockSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPasswordFocused: Bool

    let onUnlockAttempt: (String) -> Bool

    @State private var password: String = ""
    @State private var showError: Bool = false

    private var locale: Locale { AppLocalization.currentAppLocale }

    private var titleText: String {
        AppLocalization.string("profile.debug.unlock.title", locale: locale, fallback: "Debug access")
    }

    private var subtitleText: String {
        AppLocalization.string(
            "profile.debug.unlock.subtitle",
            locale: locale,
            fallback: "Enter password to show Debug in Profile."
        )
    }

    private var passwordPlaceholder: String {
        AppLocalization.string("profile.debug.unlock.password.placeholder", locale: locale, fallback: "Password")
    }

    private var unlockActionTitle: String {
        AppLocalization.string("profile.debug.unlock.action.unlock", locale: locale, fallback: "Unlock")
    }

    private var cancelActionTitle: String {
        AppLocalization.string("profile.debug.unlock.action.cancel", locale: locale, fallback: "Cancel")
    }

    private var errorText: String {
        AppLocalization.string("profile.debug.unlock.error", locale: locale, fallback: "Wrong password")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 14) {
                    FinancesGlassCard(
                        contentPadding: EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(titleText)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)

                            Text(subtitleText)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)

                            HStack(spacing: 10) {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(AppColors.textTertiary)

                                SecureField(passwordPlaceholder, text: $password)
                                    .textContentType(.password)
                                    .privacySensitive()
                                    .foregroundStyle(AppColors.textPrimary)
                                    .focused($isPasswordFocused)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        unlockIfPossible()
                                    }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )

                            if showError {
                                Text(errorText)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppColors.error)
                            }

                            Button {
                                unlockIfPossible()
                            } label: {
                                Text(unlockActionTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(AppColors.brandPrimary.opacity(0.20))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(AppColors.brandPrimary.opacity(0.35), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelActionTitle) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPasswordFocused = true
            }
        }
        .onChange(of: password) { _, _ in
            if showError {
                showError = false
            }
        }
    }

    private func unlockIfPossible() {
        let candidate = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        if onUnlockAttempt(candidate) {
            dismiss()
        } else {
            showError = true
        }
    }
}
