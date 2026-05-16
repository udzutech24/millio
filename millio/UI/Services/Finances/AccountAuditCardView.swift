import SwiftUI

private func qaL(_ key: String) -> String { FinancesL10n.tr(key) }

// MARK: - Модель данных для флоу аудита

struct AuditableAccount: Identifiable {
    enum AccountKind {
        case card(Card)
        case investment(Investment)
        case credit(Credit)
    }

    let id = UUID()
    let kind: AccountKind
    var balance: Double
    let displayName: String
    let iconName: String
    let accentColors: [Color]
    let typeLabel: String
    let typeIcon: String
    let currencyCode: String
}

// MARK: - Карточка одного счёта в флоу аудита

struct AccountAuditCardView: View {
    let account: AuditableAccount
    let index: Int
    let total: Int
    let onConfirm: () -> Void
    let onEdit: (Double) -> Void

    @State private var isEditMode = false
    @State private var editText = ""
    @State private var dragOffset: CGSize = .zero
    @FocusState private var fieldFocused: Bool

    private let confirmThreshold: CGFloat = 80
    private let editThreshold: CGFloat = -80

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            progressHeader
            Spacer()
            cardBody
                .offset(x: dragOffset.width)
                .rotationEffect(.degrees(Double(dragOffset.width) / 22))
                .gesture(swipeGesture)
                .animation(AppAnimation.springGentle, value: dragOffset.width)
            Spacer()
            if !isEditMode {
                actionButtons
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xxl)
    }

    // MARK: Прогресс-хедер

    private var progressHeader: some View {
        VStack(spacing: AppSpacing.s) {
            HStack {
                Text(qaL("finances.quick_audit.header"))
                    .font(Font.millioHeadline)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("\(index + 1) / \(total)")
                    .font(Font.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: account.accentColors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(max(total, 1)), height: 3)
                        .animation(AppAnimation.springGentle, value: index)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: Тело карточки

    private var cardBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppSpacing.xxl)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.xxl)
                        .strokeBorder(
                            LinearGradient(
                                colors: account.accentColors.map { $0.opacity(0.45) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            // Цветной оверлей при свайпе
            RoundedRectangle(cornerRadius: AppSpacing.xxl)
                .fill(AppColors.positiveColor.opacity(min(dragOffset.width / 120, 0.3)))
            RoundedRectangle(cornerRadius: AppSpacing.xxl)
                .fill(AppColors.warning.opacity(min(-dragOffset.width / 120, 0.3)))

            VStack(alignment: .leading, spacing: AppSpacing.l) {
                // Тип счёта
                Label(account.typeLabel, systemImage: account.typeIcon)
                    .font(Font.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.m)
                    .padding(.vertical, AppSpacing.xs)
                    .background(Capsule().fill(Color.white.opacity(0.1)))

                // Иконка + Название
                HStack(spacing: AppSpacing.m) {
                    Image(systemName: account.iconName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: account.accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 48, height: 48)
                        .background(
                            Circle().fill(account.accentColors.first?.opacity(0.15) ?? Color.white.opacity(0.1))
                        )
                    Text(account.displayName)
                        .font(Font.millioTitle2)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                }

                Spacer()

                // Баланс / поле ввода
                Group {
                    if isEditMode {
                        editField
                    } else {
                        balanceDisplay
                    }
                }
                .animation(AppAnimation.spring, value: isEditMode)

                Spacer()

                // Подсказка свайпа
                if !isEditMode {
                    HStack {
                        Label(qaL("finances.quick_audit.hint_edit"), systemImage: "arrow.left")
                            .font(Font.millioCaption)
                            .foregroundStyle(AppColors.textTertiary.opacity(0.45))
                        Spacer()
                        Label(qaL("finances.quick_audit.hint_confirm"), systemImage: "arrow.right")
                            .font(Font.millioCaption)
                            .foregroundStyle(AppColors.textTertiary.opacity(0.45))
                    }
                }
            }
            .padding(AppSpacing.xxl)
        }
        .frame(height: 310)
    }

    // MARK: Отображение баланса

    private var balanceDisplay: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(qaL("finances.quick_audit.current_balance"))
                .font(Font.millioCaption)
                .foregroundStyle(AppColors.textSecondary)
            Text(formattedBalance(account.balance, currency: account.currencyCode))
                .font(Font.millioDisplayLarge)
                .foregroundStyle(AppColors.textPrimary)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Поле редактирования

    private var editField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(qaL("finances.quick_audit.new_balance"))
                .font(Font.millioCaption)
                .foregroundStyle(AppColors.textSecondary)
            HStack(spacing: AppSpacing.s) {
                Text(currencySymbol(account.currencyCode))
                    .font(Font.millioTitle2)
                    .foregroundStyle(AppColors.textSecondary)
                TextField("0", text: $editText)
                    .font(Font.millioTitle2)
                    .foregroundStyle(AppColors.textPrimary)
                    .keyboardType(.decimalPad)
                    .focused($fieldFocused)
                    .tint(AppColors.brandPrimary)
            }
            .padding(AppSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.m)
                    .fill(Color.white.opacity(0.1))
            )
            Button(action: commitEdit) {
                Text(qaL("finances.quick_audit.save"))
                    .font(Font.millioHeadline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.m)
                    .background(
                        LinearGradient(colors: account.accentColors, startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.m))
            }
        }
    }

    // MARK: Кнопки действий

    private var actionButtons: some View {
        HStack(spacing: AppSpacing.m) {
            Button(action: enterEditMode) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "pencil")
                    Text(qaL("finances.quick_audit.edit"))
                }
                .font(Font.millioHeadline)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.l)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.l)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.l)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
            }
            Button(action: triggerConfirm) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "checkmark")
                    Text(qaL("finances.quick_audit.confirm"))
                }
                .font(Font.millioHeadline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.l)
                .background(
                    LinearGradient(
                        colors: [AppColors.positiveColor, Color(hex: "00E0B8")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.l))
            }
        }
    }

    // MARK: Жест свайпа

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                guard !isEditMode else { return }
                dragOffset = v.translation
            }
            .onEnded { v in
                guard !isEditMode else { return }
                if v.translation.width > confirmThreshold {
                    triggerConfirm()
                } else if v.translation.width < editThreshold {
                    withAnimation(AppAnimation.spring) { dragOffset = .zero }
                    enterEditMode()
                } else {
                    withAnimation(AppAnimation.spring) { dragOffset = .zero }
                }
            }
    }

    // MARK: Действия

    private func triggerConfirm() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dragOffset = CGSize(width: 600, height: -60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onConfirm() }
    }

    private func enterEditMode() {
        withAnimation(AppAnimation.spring) {
            isEditMode = true
            editText = balanceForEditing(account.balance)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { fieldFocused = true }
    }

    private func commitEdit() {
        let cleaned = editText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dragOffset = CGSize(width: 600, height: -60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onEdit(value) }
    }

    // MARK: Форматирование

    private func formattedBalance(_ value: Double, currency: String) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 0
        fmt.groupingSeparator = " "
        let num = fmt.string(from: NSNumber(value: abs(value))) ?? "0"
        let sign = value < 0 ? "−" : ""
        return "\(sign)\(currencySymbol(currency))\(num)"
    }

    private func balanceForEditing(_ value: Double) -> String {
        guard value != 0 else { return "" }
        let s = String(format: "%.2f", value)
        return s.hasSuffix(".00") ? String(s.dropLast(3)) : s
    }

    private func currencySymbol(_ code: String) -> String {
        switch code {
        case "RUB": return "₽"
        case "USD": return "$"
        case "EUR": return "€"
        case "CNY": return "¥"
        default: return code
        }
    }
}
