import Foundation

/// Каталог кастомных иконок для финансовых счетов.
/// Используется в AccountIconPickerSheet.
enum AccountIconSet {

    struct Category: Identifiable {
        let id: String
        let titleKey: String
        let icons: [String]
    }

    static let categories: [Category] = [
        .init(
            id: "banking",
            titleKey: "account.icon_picker.section.banking",
            icons: [
                "building.columns.fill",
                "banknote.fill",
                "creditcard.fill",
                "wallet.pass.fill",
                "lock.shield.fill",
                "dollarsign.circle.fill",
                "eurosign.circle.fill",
                "rublesign.circle.fill"
            ]
        ),
        .init(
            id: "investments",
            titleKey: "account.icon_picker.section.invest",
            icons: [
                "chart.line.uptrend.xyaxis",
                "chart.bar.fill",
                "arrow.up.right.circle.fill",
                "bitcoinsign.circle.fill",
                "chart.pie.fill",
                "trophy.fill",
                "sparkles"
            ]
        ),
        .init(
            id: "assets",
            titleKey: "account.icon_picker.section.assets",
            icons: [
                "house.fill",
                "car.fill",
                "airplane",
                "briefcase.fill",
                "crown.fill"
            ]
        ),
        .init(
            id: "savings",
            titleKey: "account.icon_picker.section.savings",
            icons: [
                "heart.fill",
                "leaf.fill",
                "flame.fill",
                "bolt.fill",
                "star.fill"
            ]
        ),
        .init(
            id: "other",
            titleKey: "account.icon_picker.section.other",
            icons: [
                "globe",
                "graduationcap.fill",
                "pawprint.fill",
                "flag.fill"
            ]
        )
    ]

    /// Все иконки плоским списком (29 штук)
    static let all: [String] = categories.flatMap(\.icons)

    /// Монограмма: из произвольной строки выжимаем 1–3 символа
    static func normalizedMonogram(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(3))
    }

    /// Проверяет, является ли iconName монограммой
    static func isMonogram(_ iconName: String) -> Bool {
        iconName.hasPrefix("monogram:")
    }

    /// Извлекает текст монограммы из iconName вида "monogram:СБ"
    static func monogramText(_ iconName: String) -> String {
        String(iconName.dropFirst("monogram:".count))
    }

    /// Формирует iconName для монограммы
    static func monogramIconName(_ text: String) -> String {
        "monogram:\(normalizedMonogram(text))"
    }

    // MARK: - Color palette

    struct ColorEntry: Identifiable {
        let id: String
        let hex: String
    }

    static let palette: [ColorEntry] = [
        .init(id: "blue",       hex: "#3B82F6"),
        .init(id: "sky",        hex: "#38BDF8"),
        .init(id: "cyan",       hex: "#06B6D4"),
        .init(id: "green",      hex: "#10B981"),
        .init(id: "lime",       hex: "#84CC16"),
        .init(id: "yellow",     hex: "#F59E0B"),
        .init(id: "orange",     hex: "#F97316"),
        .init(id: "red",        hex: "#EF4444"),
        .init(id: "pink",       hex: "#EC4899"),
        .init(id: "purple",     hex: "#8B5CF6"),
        .init(id: "indigo",     hex: "#6366F1"),
        .init(id: "gray",       hex: "#6B7280")
    ]
}
