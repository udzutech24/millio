//
//  FinancesComponents.swift
//  millio
//

import SwiftUI

struct FinancesSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppColors.textPrimary.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

struct FinancesGlassCard<Content: View>: View {
    let accentColor: Color
    let cornerRadius: CGFloat
    let contentPadding: EdgeInsets
    let content: Content

    init(
        accentColor: Color? = nil,
        cornerRadius: CGFloat = 16,
        contentPadding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
        @ViewBuilder content: () -> Content
    ) {
        self.accentColor = accentColor ?? (AppColors.financesGradient.first ?? .cyan)
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        let fillGradient = LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.07, blue: 0.11),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let glowGradient = LinearGradient(
            colors: [
                accentColor.opacity(0.18),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(glowGradient)
                            .opacity(0.6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(accentColor.opacity(0.55), lineWidth: 1)
                    )
            }
    }
}

struct FinancesRowDivider: View {
    let leadingPadding: CGFloat
    
    init(leadingPadding: CGFloat = 0) {
        self.leadingPadding = leadingPadding
    }
    
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.14))
            .padding(.leading, leadingPadding)
    }
}

struct FinancesSelectionRow: View {
    let title: String
    let isSelected: Bool
    let leadingIcon: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if isSelected {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

struct FinancesCheckboxOption: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isSelected
                            ? LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct FinancesRadioOption: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .stroke(
                        isSelected
                            ? LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isSelected {
                            Circle()
                                .fill(LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 10, height: 10)
                        }
                    }
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FinancesDestructiveConfirmationOverlay: View {
    let isPresented: Bool
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onCancel)
                    .transition(.opacity)

                FinancesGlassCard(
                    accentColor: AppColors.error,
                    cornerRadius: 24,
                    contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
                ) {
                    VStack(spacing: 18) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 42, height: 5)

                        VStack(spacing: 10) {
                            Text(title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.center)

                            Text(message)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 10) {
                            Button(action: onConfirm) {
                                Text(confirmTitle)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(AppColors.error.opacity(0.98))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(AppColors.error.opacity(0.28), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("finances.delete_confirmation.confirm")

                            Button(action: onCancel) {
                                Text(cancelTitle)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("finances.delete_confirmation.cancel")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: isPresented)
        .allowsHitTesting(isPresented)
        .accessibilityIdentifier("finances.delete_confirmation.overlay")
    }
}
