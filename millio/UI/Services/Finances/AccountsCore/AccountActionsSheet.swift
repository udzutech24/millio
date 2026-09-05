import SwiftUI

/// Один пункт bottom-sheet меню действий счёта. `subtitle` — вторая строка мелким серым текстом,
/// используется для предупреждений о последствиях действия (напр. «Закрыть досрочно»).
struct AccountActionSheetItem: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String?
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
}

/// Переиспользуемое меню действий счёта — bottom sheet вместо системного `Menu` у верхнего края.
/// Заменяет toolbar-меню деталки счёта (Коммит 1); тот же компонент рассчитан на переиспользование
/// для long-press по строке счёта в списке «Счета» (пока не подключено).
struct AccountActionsSheet: View {
    let accountName: String
    let accountTypeTitle: String
    let items: [AccountActionSheetItem]
    let onDismiss: () -> Void

    /// Высота листа — фиксированный `.height`, а не `.medium`/`.large`: число пунктов заранее
    /// известно, а системные детенты либо обрезают лист, либо оставляют пустой хвост снизу.
    private var sheetHeight: CGFloat {
        let header: CGFloat = 56
        let rows = items.reduce(CGFloat.zero) { $0 + ($1.subtitle == nil ? 52 : 68) }
        let dividers = CGFloat(max(items.count - 1, 0))
        let cancelBlock: CGFloat = 78
        return header + rows + dividers + cancelBlock + AppSpacing.l
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index != items.count - 1 {
                        Divider().background(Color.white.opacity(0.08))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            cancelButton
        }
        .padding(.bottom, AppSpacing.m)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        Text("\(accountName) · \(accountTypeTitle)")
            .font(.millioCaption2)
            .foregroundStyle(AppColors.textTertiary)
            .lineLimit(1)
            .padding(.top, AppSpacing.m)
            .padding(.bottom, AppSpacing.s)
    }

    private func row(_ item: AccountActionSheetItem) -> some View {
        Button {
            onDismiss()
            item.action()
        } label: {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: item.icon)
                    .font(.millioBody)
                    .foregroundStyle(item.isDestructive ? AppColors.error : AppColors.textPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.millioBody)
                        .foregroundStyle(item.isDestructive ? AppColors.error : AppColors.textPrimary)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.millioCaption2Regular)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, AppSpacing.xs)
    }

    private var cancelButton: some View {
        Button(L("accounts_core.detail.sheet.cancel")) {
            onDismiss()
        }
        .font(.millioBodySemibold)
        .foregroundStyle(AppColors.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.s)
    }
}
