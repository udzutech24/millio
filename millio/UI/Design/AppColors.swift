//
//  AppColors.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// Цветовая палитра приложения
/// Все цвета определены для темной темы
enum AppColors {
    // MARK: - Background Gradient
    
    /// Градиент фона приложения
    static var backgroundGradient: [Color] {
        [
            backgroundTop,
            backgroundMiddle,
            backgroundBottom
        ]
    }
    
    /// Верхняя точка градиента (черный)
    static let backgroundTop = Color.black
    
    /// Средняя точка градиента (черный)
    static let backgroundMiddle = Color.black
    
    /// Нижняя точка градиента (черный)
    static let backgroundBottom = Color.black
    
    // MARK: - Text Colors
    
    /// Основной цвет текста (белый)
    static let textPrimary = Color.white
    
    /// Вторичный цвет текста (белый с прозрачностью)
    static let textSecondary = Color.white.opacity(0.9)
    
    /// Третичный цвет текста (белый с меньшей прозрачностью)
    static let textTertiary = Color.white.opacity(0.7)
    
    // MARK: - Service Button Gradients
    
    /// Градиент для кнопки "Финансы"
    static let financesGradient = [Color.blue, Color.cyan]
    
    /// Градиент для кнопки "Курсы"
    static let coursesGradient = [Color.green, Color.mint]
    
    /// Градиент для кнопки "Кешбэк"
    static let cashbackGradient = [Color.purple, Color.pink]
    
    /// Градиент для кнопки "Кредиты"
    static let creditsGradient = [Color.blue, Color.indigo]
    
    /// Градиент для кнопки "Вода"
    static let waterGradient = [Color.cyan, Color.blue]
    
    /// Градиент для кнопки "Привычки"
    static let habitsGradient = [Color.indigo, Color.purple]
    
    /// Градиент для кнопки "Карты"
    static let cardIndexGradient = [Color.orange, Color.brown]
    
    /// Градиент для кнопки "Долги"
    static let debtsGradient = [Color.red, Color.orange]
    
    /// Градиент для кнопки "Активы"
    static let investmentsGradient = [Color.yellow, Color.orange]
    
    /// Градиент для кнопки "Планировщик"
    static let plannedExpensesGradient = [Color.teal, Color.cyan]
    
    /// Градиент для кнопки "Кэшфлоу"
    static let cashflowGradient = [Color.blue, Color.purple]
    
    /// Градиент для кнопки "Игры"
    static let gamesGradient = [Color.green, Color.cyan]
    
    // MARK: - Action Button Gradients
    
    /// Градиент для кнопки "Расход" (синий -> розовый)
    static let expenseGradient = [Color(hex: "197CE6").opacity(0.5), Color(hex: "FF02A6").opacity(0.5)]
    
    /// Градиент для кнопки "Доход" (зеленый -> синий)
    static let incomeGradient = [Color(hex: "19E694").opacity(0.5), Color(hex: "0947E4").opacity(0.5)]
    
    // MARK: - UI Elements
    
    /// Цвет для иконок в кнопках действий (белый)
    static let iconColor = Color.white
    
    /// Цвет фона для иконок в кнопках действий
    static let iconBackground = Color.white.opacity(0.2)
    
    /// Цвет для ошибок
    static let error = Color.red
    
    /// Цвет для предупреждений
    static let warning = Color.orange
}
