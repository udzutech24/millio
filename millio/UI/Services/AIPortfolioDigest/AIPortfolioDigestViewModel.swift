//
//  AIPortfolioDigestViewModel.swift
//  millio
//

import Combine
import Foundation
import SwiftUI

/// Дайджест портфеля: цифры считаются на устройстве и видны всегда, текст модели — опционально,
/// дисклеймер — в любом состоянии. В сеть — только при явном открытии экрана и смене окна.
@MainActor
final class AIPortfolioDigestViewModel: ObservableObject {
    @Published private(set) var window: AIPortfolioWindow
    @Published private(set) var figures: AIPortfolioFigures?
    @Published private(set) var text: AIPortfolioDigestText?
    @Published private(set) var isLoadingText = false
    @Published private(set) var serverDisclaimer: String?

    let currency: String

    /// Комплаенс: дисклеймер есть ВСЕГДА — серверный, если пришёл, иначе локальная константа
    /// (офлайн, эндпоинт не задеплоен, ошибка, пустой портфель).
    var disclaimer: String {
        let trimmed = serverDisclaimer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L("ai.portfolio.disclaimer") : trimmed
    }

    private struct Outcome {
        let text: AIPortfolioDigestText?
        let disclaimer: String?

        static let numbersOnly = Outcome(text: nil, disclaimer: nil)
    }

    private let figuresProvider: @MainActor (AIPortfolioWindow) -> AIPortfolioFigures?
    private let client: any AIPortfolioDigestClient
    private let locale: () -> Locale

    /// Цифры и исход запроса живут на окно и на время жизни экрана: возврат из позиции и
    /// переключение окон туда-обратно в сеть не ходят — кэша на сервере нет, каждый вызов платный.
    private var figuresByWindow: [AIPortfolioWindow: AIPortfolioFigures] = [:]
    private var emptyWindows: Set<AIPortfolioWindow> = []
    private var outcomes: [AIPortfolioWindow: Outcome] = [:]
    private var inFlight: Set<AIPortfolioWindow> = []
    private var didOpen = false
    /// Последняя запущенная загрузка текста — чтобы тесты могли её дождаться.
    private(set) var loadTask: Task<Void, Never>?

    init(
        currency: String,
        figuresProvider: @escaping @MainActor (AIPortfolioWindow) -> AIPortfolioFigures?,
        client: any AIPortfolioDigestClient,
        window: AIPortfolioWindow = .month,
        locale: @escaping () -> Locale = { AppLocalization.currentAppLocale }
    ) {
        self.currency = currency
        self.figuresProvider = figuresProvider
        self.client = client
        self.window = window
        self.locale = locale
        // Цифры — сразу, без сети: модель создаётся ровно в момент открытия экрана.
        self.figures = resolveFigures(for: window)
    }

    // MARK: - Действия

    /// Появление экрана. Повторные вызовы (возврат из позиции) сеть не трогают.
    func open() {
        guard !didOpen else { return }
        didOpen = true
        requestTextIfNeeded(for: window)
    }

    func select(_ window: AIPortfolioWindow) {
        guard window != self.window else { return }
        self.window = window
        figures = resolveFigures(for: window)
        guard didOpen else { return }
        requestTextIfNeeded(for: window)
    }

    // MARK: - Текст

    private func requestTextIfNeeded(for window: AIPortfolioWindow) {
        if let outcome = outcomes[window] {
            apply(outcome)
            return
        }
        apply(.numbersOnly)
        // Пустой портфель — формулировать нечего, запрос не отправляем.
        guard let figures = resolveFigures(for: window) else { return }
        guard client.isAvailable else {
            outcomes[window] = .numbersOnly
            return
        }

        isLoadingText = true
        guard inFlight.insert(window).inserted else { return }

        let request = AIPortfolioDigestPayloadBuilder.makeRequest(figures: figures, locale: locale())
        let client = client
        loadTask = Task { [weak self] in
            let outcome: Outcome
            do {
                let response = try await client.digest(request)
                outcome = Outcome(text: response.text, disclaimer: response.disclaimer)
            } catch {
                // Офлайн, 429, 5xx, битый контракт — одинаково: цифры и локальный дисклеймер.
                outcome = .numbersOnly
            }
            self?.finish(window, with: outcome)
        }
    }

    private func finish(_ window: AIPortfolioWindow, with outcome: Outcome) {
        inFlight.remove(window)
        outcomes[window] = outcome
        guard window == self.window else { return }
        apply(outcome)
    }

    private func apply(_ outcome: Outcome) {
        text = outcome.text
        serverDisclaimer = outcome.disclaimer
        isLoadingText = false
    }

    // MARK: - Цифры

    private func resolveFigures(for window: AIPortfolioWindow) -> AIPortfolioFigures? {
        if let cached = figuresByWindow[window] { return cached }
        if emptyWindows.contains(window) { return nil }
        let computed = figuresProvider(window)
        if let computed {
            figuresByWindow[window] = computed
        } else {
            emptyWindows.insert(window)
        }
        return computed
    }
}
