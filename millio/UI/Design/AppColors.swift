//
//  AppColors.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

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
    
    /// Верхняя точка градиента (темно-синий)
    static let backgroundTop = Color(red: 0.1, green: 0.2, blue: 0.35)
    
    /// Средняя точка градиента (сине-зеленый)
    static let backgroundMiddle = Color(red: 0.15, green: 0.25, blue: 0.4)
    
    /// Нижняя точка градиента (темно-фиолетовый)
    static let backgroundBottom = Color(red: 0.2, green: 0.15, blue: 0.3)
    
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
    
    /// Градиент для кнопки "Игры"
    static let gamesGradient = [Color.green, Color.cyan]
    
    // MARK: - Action Button Gradients
    
    /// Градиент для кнопки "Расход"
    static let expenseGradient = [Color.purple, Color.pink]
    
    /// Градиент для кнопки "Доход"
    static let incomeGradient = [Color.blue, Color.cyan]
    
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
