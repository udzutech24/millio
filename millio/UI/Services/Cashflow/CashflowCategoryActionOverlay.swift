//
//  CashflowCategoryActionOverlay.swift
//  millio
//

import SwiftUI

struct CashflowCategoryActionOverlay: View {
    let isPresented: Bool
    let categoryName: String
    let categoryIcon: String
    let accentColor: Color
    let primaryActionTitle: String?
    let primaryActionIcon: String?
    let onPrimaryAction: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryActionIcon: String?
    let onSecondaryAction: (() -> Void)?
    let onEdit: () -> Void
    let deleteActionTitle: String?
    let deleteActionIcon: String?
    let onDelete: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.56)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .transition(.opacity)

                FinancesGlassCard(
                    accentColor: accentColor,
                    cornerRadius: 26,
                    contentPadding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
                ) {
                    VStack(spacing: 16) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 42, height: 5)

                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 48, height: 48)
                                .overlay {
                                    CashflowCategoryIconView(
                                        icon: categoryIcon,
                                        fontSize: 22,
                                        fontWeight: .semibold,
                                        tint: AnyShapeStyle(accentColor)
                                    )
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(categoryName)
                                    .font(.system(size: 21, weight: .bold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .multilineTextAlignment(.leading)

                                Text(String(localized: "cashflow.category.actions.message"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()
                        }

                        VStack(spacing: 10) {
                            if let primaryActionTitle, let primaryActionIcon, let onPrimaryAction {
                                actionButton(
                                    title: primaryActionTitle,
                                    systemImage: primaryActionIcon,
                                    tint: accentColor,
                                    action: onPrimaryAction
                                )
                            }

                            if let secondaryActionTitle, let secondaryActionIcon, let onSecondaryAction {
                                actionButton(
                                    title: secondaryActionTitle,
                                    systemImage: secondaryActionIcon,
                                    tint: AppColors.textPrimary,
                                    action: onSecondaryAction
                                )
                            }

                            actionButton(
                                title: String(localized: "cashflow.common.edit"),
                                systemImage: "pencil",
                                tint: AppColors.textPrimary,
                                action: onEdit
                            )

                            if let onDelete {
                                actionButton(
                                    title: deleteActionTitle ?? String(localized: "cashflow.category.actions.delete"),
                                    systemImage: deleteActionIcon ?? "trash",
                                    tint: AppColors.error,
                                    action: onDelete
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isPresented)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))

                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(tint.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
