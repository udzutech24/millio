import SwiftUI

/// Бейдж иконки финансового счёта.
/// Приоритет: монограмма → SF Symbol (custom) → SF Symbol (fallback)
struct AccountIconBadgeView: View {

    /// SF Symbol name или "monogram:СБ". nil = использовать fallback
    let iconName: String?
    /// Hex цвет иконки. nil = financesGradient
    let iconColor: String?
    /// Иконка по умолчанию (SF Symbol), используется когда iconName == nil
    let fallback: String
    let size: CGFloat

    /// Когда true — цвет иконки заменяется на AppColors.error (для долговых счетов)
    let isError: Bool

    init(
        iconName: String?,
        iconColor: String?,
        fallback: String,
        size: CGFloat = 32,
        isError: Bool = false
    ) {
        self.iconName = iconName
        self.iconColor = iconColor
        self.fallback = fallback
        self.size = size
        self.isError = isError
    }

    private var resolvedIconName: String {
        guard let name = iconName, !name.isEmpty else { return fallback }
        return name
    }

    private var isMonogram: Bool {
        AccountIconSet.isMonogram(resolvedIconName)
    }

    private var monogramText: String {
        AccountIconSet.monogramText(resolvedIconName)
    }

    private var iconFontSize: CGFloat { size * 0.41 }
    private var monogramFontSize: CGFloat { size * 0.35 }
    private var cornerRadius: CGFloat { size * 0.31 }

    var body: some View {
        Group {
            if isMonogram {
                Text(monogramText)
                    .font(.system(size: monogramFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(foregroundStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: resolvedIconName)
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .foregroundStyle(foregroundStyle)
            }
        }
        .frame(width: size, height: size)
    }

    private var foregroundStyle: some ShapeStyle {
        if isError {
            return AnyShapeStyle(AppColors.error)
        } else if let hex = iconColor, !hex.isEmpty {
            return AnyShapeStyle(Color(hex: hex))
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: AppColors.financesGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        AccountIconBadgeView(iconName: nil, iconColor: nil, fallback: "creditcard.fill")
        AccountIconBadgeView(iconName: "bitcoinsign.circle.fill", iconColor: "#F59E0B", fallback: "creditcard.fill")
        AccountIconBadgeView(iconName: "monogram:СБ", iconColor: "#10B981", fallback: "creditcard.fill")
        AccountIconBadgeView(iconName: "house.fill", iconColor: nil, fallback: "creditcard.fill", size: 44)
    }
    .padding()
    .background(Color.black)
}
