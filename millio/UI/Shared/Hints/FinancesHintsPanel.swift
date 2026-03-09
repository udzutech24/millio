//
//  FinancesHintsPanel.swift
//  millio
//
//  Единый стиль подсказок (hints) с возможностью скрыть.
//  Визуально соответствует "пиллам" с обводкой (как на референсе в Figma/скринах).
//

import SwiftUI

struct FinancesHintItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case warning
        case recommendation

        var systemImage: String {
            switch self {
            case .info:
                return "info.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .recommendation:
                return "sparkles"
            }
        }

        var accentColor: Color {
            switch self {
            case .info:
                return AppColors.textSecondary
            case .warning:
                return AppColors.error
            case .recommendation:
                return Color(hex: "6DFFC7")
            }
        }
    }

    let id: String
    let kind: Kind
    let text: String

    init(id: String, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

struct FinancesHintsPanel: View {
    private let title: String
    private let prefs: HintsVisibilityPrefs
    private let items: [FinancesHintItem]
    private let accentColor: Color

    @State private var isHidden: Bool

    init(
        title: String = "Hints",
        prefsKey: String,
        items: [FinancesHintItem],
        accentColor: Color = AppColors.textSecondary,
        defaults: UserDefaults = .standard
    ) {
        self.title = title
        self.prefs = HintsVisibilityPrefs(key: prefsKey, defaults: defaults)
        self.items = items
        self.accentColor = accentColor
        _isHidden = State(initialValue: HintsVisibilityPrefs(key: prefsKey, defaults: defaults).isHidden)
    }

    var body: some View {
        if !isHidden, !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        FinancesHintPill(item: item)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(accentColor.opacity(0.55), lineWidth: 1)
                    )
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: 8)

            Button {
                isHidden = true
                prefs.setHidden(true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide hints")
        }
    }
}

private struct FinancesHintPill: View {
    let item: FinancesHintItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.kind.accentColor)
                .frame(width: 14)
                .padding(.top, 1)

            Text(item.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(item.kind.accentColor.opacity(0.65), lineWidth: 1)
                )
        )
    }
}

