import SwiftUI

/// Одно действие счёта — общее описание и для панели (`AccountActionsRow`), и для «···»
/// (`AccountActionsSheet`): раньше на два способа показать одно и то же действие было два типа.
/// `isProminent` — единственная акцентная кнопка ряда (основной путь пользователя на экране),
/// `isEnabled` гасит кнопку, не убирая её из ряда: исчезающая кнопка сдвигает соседние и ломает
/// мышечную память. `subtitle` показывается только в листе — второй строкой о последствиях.
struct AccountActionItem: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String?
    let icon: String
    var isProminent: Bool = false
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        isProminent: Bool = false,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isProminent = isProminent
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// Единая панель действий деталки счёта: круглые иконки 46pt с подписью под ними.
/// Один стиль для всех типов счетов (решение владельца 06.09.2026) — раньше их было три:
/// круглые у инвестиций, pill-скролл у остальных, у вклада и кредита панели не было вовсе.
struct AccountActionsRow: View {
    let items: [AccountActionItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.m) {
                ForEach(items) { item in
                    Button(action: item.action) {
                        Self.label(icon: item.icon, title: item.title, isProminent: item.isProminent, isDestructive: item.isDestructive)
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.isEnabled)
                    .opacity(item.isEnabled ? 1 : 0.4)
                }
            }
            // Ряд из 3–4 кнопок помещается на экран целиком — без этого ScrollView всё равно
            // «пружинит» по горизонтали и выглядит как обрезанный список.
            .padding(.vertical, AppSpacing.xs)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// Круг 46pt + подпись 11,5pt под ним. `#1C1C1E` — тот же ad-hoc hex, что уже использовал
    /// экран деталки для нейтрального круга: токена под этот точный цвет в `AppColors` нет.
    static func label(icon: String, title: String?, isProminent: Bool, isDestructive: Bool = false) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.millioBodySemibold)
                .foregroundStyle(isProminent ? Color.white : (isDestructive ? AppColors.error : AppColors.textPrimary))
                .frame(width: 46, height: 46)
                .background(Circle().fill(isProminent ? AppColors.positiveColor : Color(hex: "1C1C1E")))
            if let title {
                Text(title)
                    .font(.millioCaption2Medium)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: 76)
            }
        }
    }
}
