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

enum FinanceRefreshAction: CaseIterable {
    case quotes
    case stocks

    var titleKey: String {
        switch self {
        case .quotes:
            return "finances.main.refresh_quotes"
        case .stocks:
            return "finances.main.refresh_stocks"
        }
    }

    var iconName: String {
        switch self {
        case .quotes:
            return "dollarsign.arrow.circlepath"
        case .stocks:
            return "chart.line.uptrend.xyaxis.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .quotes:
            return FinanceScreenChrome.refreshQuotesTint
        case .stocks:
            return FinanceScreenChrome.refreshStocksTint
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .quotes:
            return "finances.refresh_overlay.quotes"
        case .stocks:
            return "finances.refresh_overlay.stocks"
        }
    }
}

struct FinanceRefreshActionOverlay: View {
    let isPresented: Bool
    let isLoading: Bool
    let onSelect: (FinanceRefreshAction) -> Void
    let onDismiss: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .transition(.opacity)

                FinancesGlassCard(
                    accentColor: FinanceScreenChrome.refreshOverlayAccent,
                    cornerRadius: FinanceScreenChrome.actionSheetCornerRadius,
                    contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
                ) {
                    VStack(spacing: 12) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 38, height: 5)

                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(FinanceScreenChrome.refreshOverlayAccent)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(FinancesL10n.tr("finances.refresh_sheet.title", locale: locale))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)

                                Text(FinancesL10n.tr("finances.refresh_sheet.subtitle", locale: locale))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }

                        VStack(spacing: 8) {
                            ForEach(FinanceRefreshAction.allCases, id: \.titleKey) { action in
                                refreshActionButton(for: action)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 598)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isPresented)
        .allowsHitTesting(isPresented)
    }

    private func refreshActionButton(for action: FinanceRefreshAction) -> some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 20)

                Text(LocalizedStringKey(action.titleKey))
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(action.tintColor)
                }
            }
            .foregroundStyle(isLoading ? AppColors.textSecondary : action.tintColor)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.055),
                                Color.white.opacity(0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(action.tintColor.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityIdentifier(action.accessibilityIdentifier)
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
