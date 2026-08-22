//
//  ConverterViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import Combine
import Network
#if os(iOS)
import UIKit
import AudioToolbox
#endif

struct ConverterShareHistoryItem: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let activeCode: String
    let inputText: String
    let selectedCodes: [String]
    let imageFileName: String?
    var shareTitle: String?
    var note: String?
}

// MARK: - Converter State

struct ConverterState {
    // Валюты
    var selectedCurrencies: [String] = []
    var activeCode: String = "TRY"
    var allRates: [String: Double] = ["USD": 1.0]
    
    // Ввод
    var inputText: String = "1200"
    
    // UI состояния
    var showPicker: Bool = false
    var replaceIndex: Int? = nil
    var searchText: String = ""
    var showFractionDialog: Bool = false
    var showSettingsSheet: Bool = false
    
    // Настройки
    var rateSource: RateSource = .millio
    var showOfflineBadge: Bool = true
    var hapticsEnabled: Bool = true
    var isOffline: Bool = false
    var isFetchingRates: Bool = false
    var fractionDigits: Int = 2
    
    // Калькулятор
    var accumulator: Double? = nil
    var pendingOp: String? = nil
    var entering: Bool = true
    var justEvaluated: Bool = false
    var expressionText: String = ""
    var calcModeOn: Bool = false
    
    // Share
    var shareImage: UIImage? = nil
    var shareDraftMessage: String = ""
    var showSharePreviewSheet: Bool = false
    var showShareSheet: Bool = false
    var shareHistory: [ConverterShareHistoryItem] = []
    var showShareHistorySheet: Bool = false
    
    // Toast
    var toastMessage: String? = nil
    var showToast: Bool = false
}

// MARK: - Converter ViewModel

@MainActor
final class ConverterViewModel: ViewModelProtocol {
    @Published var state = ConverterState()
    
    // Persisted settings (using UserDefaults instead of @AppStorage for MVVM compliance)
    private let defaults = UserDefaults.standard
    private let currencyService: CurrencyRateService
    
    private var selectedCodesRaw: String {
        get { defaults.string(forKey: "conv_selected_codes") ?? "RUB,USD,EUR,TRY,GBP,KZT" }
        set {
            defaults.set(newValue, forKey: "conv_selected_codes")
            CurrencyWidgetSyncService.setString(newValue, forKey: CurrencyWidgetShared.Keys.selectedCodes)
        }
    }
    
    private var storedActive: String {
        get { defaults.string(forKey: "conv_active_code") ?? "TRY" }
        set {
            defaults.set(newValue, forKey: "conv_active_code")
            CurrencyWidgetSyncService.setString(newValue, forKey: CurrencyWidgetShared.Keys.activeCode)
        }
    }
    
    private var storedInput: String {
        get { defaults.string(forKey: "conv_input_text") ?? "1200" }
        set {
            defaults.set(newValue, forKey: "conv_input_text")
            CurrencyWidgetSyncService.setString(newValue, forKey: CurrencyWidgetShared.Keys.inputText)
        }
    }
    
    private var storedFractionDigits: Int {
        get {
            if defaults.object(forKey: "conv_fraction_digits") == nil {
                return 2
            }
            return defaults.integer(forKey: "conv_fraction_digits")
        }
        set {
            defaults.set(newValue, forKey: "conv_fraction_digits")
            CurrencyWidgetSyncService.setInt(newValue, forKey: "conv_fraction_digits")
        }
    }
    
    /// Конвертер использует общий источник, чтобы его суммы совпадали с финансовыми экранами.
    var rateSourceDisplayLabel: String {
        return state.rateSource.title
    }
    
    private var storedShowOfflineBadge: Bool {
        get { defaults.object(forKey: "conv_show_offline_badge") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "conv_show_offline_badge")
            CurrencyWidgetSyncService.setBool(newValue, forKey: "conv_show_offline_badge")
        }
    }
    
    private var storedHapticsEnabled: Bool {
        get { defaults.object(forKey: "conv_haptics_enabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "conv_haptics_enabled")
            CurrencyWidgetSyncService.setBool(newValue, forKey: "conv_haptics_enabled")
        }
    }

    private var storedShareHistoryData: Data? {
        get { defaults.data(forKey: "conv_share_history") }
        set { defaults.set(newValue, forKey: "conv_share_history") }
    }

    private var storedShareSequence: Int {
        get {
            guard defaults.object(forKey: "conv_share_sequence") != nil else { return 0 }
            return defaults.integer(forKey: "conv_share_sequence")
        }
        set {
            defaults.set(newValue, forKey: "conv_share_sequence")
        }
    }
    
    private var storedLastRatesTS: Double {
        get {
            let key = CurrencyWidgetShared.Keys.lastRatesTimestamp(for: state.rateSource.rawValue)
            return defaults.double(forKey: key)
        }
        set {
            let key = CurrencyWidgetShared.Keys.lastRatesTimestamp(for: state.rateSource.rawValue)
            defaults.set(newValue, forKey: key)
            CurrencyWidgetSyncService.setLastRatesTimestamp(newValue, forSource: state.rateSource.rawValue)
        }
    }
    
    private var storedCachedRates: [String: Double] {
        get {
            let key = CurrencyWidgetShared.Keys.cachedRates(for: state.rateSource.rawValue)
            return CurrencyWidgetShared.decodeRates(from: defaults.object(forKey: key))
        }
        set {
            let key = CurrencyWidgetShared.Keys.cachedRates(for: state.rateSource.rawValue)
            defaults.set(newValue, forKey: key)
            CurrencyWidgetSyncService.setRates(newValue, forSource: state.rateSource.rawValue)
        }
    }
    
    private let maxCurrencies: Int = 6
    private let maxShareHistoryItems: Int = 30

    /// CoinGecko IDs для поддерживаемых криптовалют в конвертере.
    /// Используется для догрузки crypto-курсов поверх фиатных источников.
    private let cryptoCodeToId: [String: String] = [
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "USDT": "tether",
        "USDC": "usd-coin",
        "BNB": "binancecoin",
        "SOL": "solana",
        "XRP": "ripple",
        "ADA": "cardano",
        "DOGE": "dogecoin",
        "TON": "toncoin",
        "TRX": "tron",
        "DOT": "polkadot",
        "MATIC": "polygon",
        "AVAX": "avalanche-2",
        "SHIB": "shiba-inu",
        "LTC": "litecoin",
        "BCH": "bitcoin-cash",
        "ATOM": "cosmos",
        "LINK": "chainlink",
        "XLM": "stellar",
        "ETC": "ethereum-classic",
        "FIL": "filecoin",
        "NEAR": "near",
        "HBAR": "hedera-hashgraph",
        "APT": "aptos",
        "OP": "optimism",
        "ARB": "arbitrum",
        "ICP": "internet-computer",
        "SUI": "sui",
        "PEPE": "pepe"
    ]
    
    private var decSep: String { ConverterL10n.decimalSeparator }
    private var supportedCryptoCodes: Set<String> { Set(cryptoCodeToId.keys) }
    
    var currentFractionDigits: Int {
        max(0, min(8, storedFractionDigits))
    }

    var shareDraftTitle: String {
        ConverterL10n.shareTitle(index: storedShareSequence + 1)
    }
    
    init(currencyService: CurrencyRateService) {
        self.currencyService = currencyService
        onAppearInit()
        // Проверяем валюты после инициализации, если курсы уже загружены
        if state.allRates.count > 1 {
            filterSelectedCurrenciesToAvailable()
        }
    }

    convenience init() {
        self.init(currencyService: .shared)
    }

    convenience init(rateRepository: RateRepositoryProtocol) {
        self.init(currencyService: CurrencyRateService(rateSource: .millio, rateRepository: rateRepository))
    }
    
    // MARK: - Actions
    
    enum Action {
        // Валюты
        case selectCurrency(String)
        case addCurrency
        case replaceCurrency(Int)
        case removeCurrency(Int)
        case removeLastCurrency
        case applyPickerSelection(String)
        
        // Ввод
        case updateInputText(String)
        case appendDigit(String)
        case appendZero
        case appendComma
        case backspace
        case clearAll
        
        // Калькулятор
        case operation(String)
        case equal
        case percent
        case toggleCalcMode
        
        // Настройки
        case setRateSource(RateSource)
        case setShowOfflineBadge(Bool)
        case setHapticsEnabled(Bool)
        case setFractionDigits(Int)
        case refreshRates(force: Bool)
        
        // UI
        case showPicker(Int?)
        case hidePicker
        case showSettingsSheet
        case hideSettingsSheet
        case showFractionDialog
        case hideFractionDialog
        case updateSearchText(String)
        
        // Share
        case prepareShare
        case hideSharePreview
        case updateShareDraftMessage(String)
        case sendShareFromPreview
        case shareCompleted(Bool, Data?)
        case showShareHistory
        case hideShareHistory
        case clearShareHistory
        case deleteShareHistoryItem(UUID)
    }
    
    func handle(_ action: Action) {
        let previousInput = state.inputText
        defer { persistInputIfNeeded(previousInput: previousInput) }
        
        switch action {
        case .selectCurrency(let code):
            state.activeCode = code
            state.calcModeOn = false
            storedActive = code
            mirrorToICloud(key: "conv_active_code", value: code)
            
        case .addCurrency:
            state.replaceIndex = nil
            state.searchText = ""
            state.showPicker = true
            
        case .replaceCurrency(let index):
            state.replaceIndex = index
            state.searchText = ""
            state.showPicker = true
            
        case .removeCurrency(let index):
            removeCurrency(at: index)
            
        case .removeLastCurrency:
            removeLastCurrency()
            
        case .applyPickerSelection(let code):
            applyPickerSelection(code)
            
        case .updateInputText(let text):
            state.inputText = text
            state.entering = true
            state.justEvaluated = false
            
        case .appendDigit(let digit):
            append(digit)
            
        case .appendZero:
            append("0")
            
        case .appendComma:
            appendComma()
            
        case .backspace:
            backspace()
            
        case .clearAll:
            clearAll()
            
        case .operation(let symbol):
            op(symbol)
            
        case .equal:
            equal()
            
        case .percent:
            percent()
            
        case .toggleCalcMode:
            state.calcModeOn.toggle()
            
        case .setRateSource(let source):
            currencyService.setRateSource(source)
            state.rateSource = currencyService.rateSource
            let cachedRates = currencyService.currentRateSnapshot()?.rates ?? [:]
            if cachedRates.count > 1 {
                state.allRates = cachedRates
                filterSelectedCurrenciesToAvailable()
            }
            Task { await fetchRates(haptic: false, force: true) }
            
        case .setShowOfflineBadge(let value):
            state.showOfflineBadge = value
            storedShowOfflineBadge = value
            mirrorToICloud(key: "conv_show_offline_badge", value: value ? "1" : "0")
            
        case .setHapticsEnabled(let value):
            state.hapticsEnabled = value
            storedHapticsEnabled = value
            mirrorToICloud(key: "conv_haptics_enabled", value: value ? "1" : "0")
            
        case .setFractionDigits(let digits):
            storedFractionDigits = digits
            state.fractionDigits = digits
            
        case .refreshRates(let force):
            Task { await fetchRates(haptic: false, force: force) }
            
        case .showPicker(let index):
            state.replaceIndex = index
            state.searchText = ""
            state.showPicker = true
            
        case .hidePicker:
            state.showPicker = false
            
        case .showSettingsSheet:
            state.showSettingsSheet = true
            
        case .hideSettingsSheet:
            state.showSettingsSheet = false
            
        case .showFractionDialog:
            state.showFractionDialog = true
            
        case .hideFractionDialog:
            state.showFractionDialog = false
            
        case .updateSearchText(let text):
            state.searchText = text
            
        case .prepareShare:
            state.shareDraftMessage = ""
            state.showSharePreviewSheet = true

        case .hideSharePreview:
            state.showSharePreviewSheet = false

        case .updateShareDraftMessage(let text):
            state.shareDraftMessage = text

        case .sendShareFromPreview:
            state.showSharePreviewSheet = false
            state.showShareSheet = true

        case .shareCompleted(let completed, let imageData):
            state.showShareSheet = false
            if completed {
                let title = shareDraftTitle
                let note = state.shareDraftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                appendShareHistoryEntry(
                    imageData: imageData,
                    shareTitle: title,
                    note: note.isEmpty ? nil : note
                )
                storedShareSequence += 1
            }
            state.shareDraftMessage = ""

        case .showShareHistory:
            state.showShareHistorySheet = true

        case .hideShareHistory:
            state.showShareHistorySheet = false

        case .clearShareHistory:
            for item in state.shareHistory {
                deleteHistoryImage(fileName: item.imageFileName)
            }
            state.shareHistory = []
            persistShareHistory()

        case .deleteShareHistoryItem(let id):
            guard let index = state.shareHistory.firstIndex(where: { $0.id == id }) else { return }
            let item = state.shareHistory.remove(at: index)
            deleteHistoryImage(fileName: item.imageFileName)
            persistShareHistory()
        }
    }
    
    // MARK: - Initialization
    
    private func onAppearInit() {
        state.selectedCurrencies = selectedCodesRaw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
        if state.selectedCurrencies.isEmpty {
            state.selectedCurrencies = ["RUB", "USD", "EUR", "TRY", "GBP", "KZT"]
        }
        state.activeCode = storedActive.isEmpty ? "TRY" : storedActive
        state.inputText = storedInput.isEmpty ? "0" : storedInput
        
        state.rateSource = currencyService.rateSource
        state.showOfflineBadge = storedShowOfflineBadge
        state.hapticsEnabled = storedHapticsEnabled
        if state.expressionText.isEmpty {
            state.expressionText = state.inputText
        }
        
        // Синхронизация состояния
        state.fractionDigits = storedFractionDigits
        state.shareHistory = loadShareHistory()
        
        let cachedRates = currencyService.currentRateSnapshot()?.rates ?? [:]
        if cachedRates.count > 1 {
            state.allRates = cachedRates
            filterSelectedCurrenciesToAvailable()
        }
        
        syncWidgetConverterSnapshot()
    }
    
    // MARK: - Currency Management
    
    func displayValue(for code: String) -> String {
        guard let input = parseAmount(state.inputText) else { return "0" }
        let amountInCode = convert(amount: input, from: state.activeCode, to: code)
        return formatPlain(amountInCode, maxFrac: currentFractionDigits)
    }

    /// Форматированное значение текущего ввода для UI:
    /// добавляет разделители тысяч, но сохраняет "живую" дробную часть как ввел пользователь.
    var formattedInputText: String {
        formatInputForDisplay(state.inputText)
    }

    func localizedInputText(_ raw: String) -> String {
        formatInputForDisplay(raw)
    }
    
    private func convert(amount: Double, from: String, to: String) -> Double {
        guard let rFrom = rateUSD(from), let rTo = rateUSD(to), rFrom > 0 else { return 0 }
        let inUSD = (from == "USD") ? amount : amount / rFrom
        return (to == "USD") ? inUSD : inUSD * rTo
    }
    
    private func rateUSD(_ code: String) -> Double? {
        code == "USD" ? 1 : state.allRates[code]
    }
    
    private func removeCurrency(at index: Int) {
        guard state.selectedCurrencies.indices.contains(index) else { return }
        let removed = state.selectedCurrencies.remove(at: index)
        if removed == state.activeCode {
            state.activeCode = state.selectedCurrencies.first ?? "USD"
            storedActive = state.activeCode
            mirrorToICloud(key: "conv_active_code", value: state.activeCode)
        }
        persistSelected()
    }
    
    private func removeLastCurrency() {
        // Удаляем активную валюту, а не последнюю
        guard let activeIndex = state.selectedCurrencies.firstIndex(of: state.activeCode),
              state.selectedCurrencies.count > 1 else { return }
        removeCurrency(at: activeIndex)
    }
    
    private func persistSelected() {
        selectedCodesRaw = state.selectedCurrencies.joined(separator: ",")
        mirrorToICloud(key: "conv_selected_codes", value: selectedCodesRaw)
    }
    
    /// Фильтрует выбранные валюты, оставляя только те, что доступны в текущем источнике
    private func filterSelectedCurrenciesToAvailable() {
        // Получаем список доступных валют (USD всегда доступен)
        let availableCodes = Set(state.allRates.keys).union(["USD"]).union(supportedCryptoCodes)
        
        // Фильтруем выбранные валюты
        let filtered = state.selectedCurrencies.filter { availableCodes.contains($0) }
        
        // Если после фильтрации список пуст, добавляем базовые валюты
        if filtered.isEmpty {
            // Добавляем валюты, которые обычно есть во всех источниках
            let commonCurrencies = ["USD", "EUR", "GBP", "JPY", "CNY"]
            state.selectedCurrencies = commonCurrencies.filter { availableCodes.contains($0) }
        } else {
            state.selectedCurrencies = filtered
        }
        
        // Проверяем активную валюту
        if !availableCodes.contains(state.activeCode) {
            // Если активная валюта недоступна, выбираем первую из списка или USD
            state.activeCode = state.selectedCurrencies.first ?? "USD"
            storedActive = state.activeCode
        }
        
        // Сохраняем обновленный список
        persistSelected()
    }
    
    private func applyPickerSelection(_ code: String) {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else { return }

        // Курсы: список выбранных валют должен оставаться уникальным.
        // При replace не даем выбрать код, который уже есть в другом слоте.
        if let replaceIndex = state.replaceIndex,
           state.selectedCurrencies.indices.contains(replaceIndex),
           state.selectedCurrencies.enumerated().contains(where: { index, existingCode in
               index != replaceIndex && existingCode.uppercased() == normalizedCode
           }) {
            return
        }

        if let idx = state.replaceIndex, state.selectedCurrencies.indices.contains(idx) {
            state.selectedCurrencies[idx] = normalizedCode
        } else {
            guard state.selectedCurrencies.count < maxCurrencies else { return }
            if !state.selectedCurrencies.contains(normalizedCode) {
                state.selectedCurrencies.append(normalizedCode)
            }
        }
        if !state.selectedCurrencies.contains(state.activeCode) {
            state.activeCode = state.selectedCurrencies.first ?? "USD"
        }
        storedActive = state.activeCode
        mirrorToICloud(key: "conv_active_code", value: state.activeCode)
        persistSelected()
        state.showPicker = false

        if supportedCryptoCodes.contains(normalizedCode), state.allRates[normalizedCode] == nil {
            Task { [weak self] in
                await self?.fetchRates(force: true)
            }
        }
    }
    
    // MARK: - Calculator Logic
    
    private func clearAll() {
        state.inputText = "0"
        state.accumulator = nil
        state.pendingOp = nil
        state.entering = true
        state.justEvaluated = false
        state.expressionText = ""
    }
    
    private func backspace() {
        if state.justEvaluated {
            state.entering = true
            state.justEvaluated = false
        }
        // Не удаляем, если остался только "0"
        if state.inputText.count > 1 {
            state.inputText.removeLast()
        } else if state.inputText != "0" && !state.inputText.isEmpty {
            state.inputText.removeLast()
        }
        if state.inputText.isEmpty || state.inputText == "-" { state.inputText = "0" }
        
        // Обновляем expressionText синхронно с inputText
        if !state.expressionText.isEmpty {
            state.expressionText.removeLast()
        }
        if state.expressionText.isEmpty { state.expressionText = state.inputText }
    }
    
    private func append(_ s: String) {
        if state.justEvaluated {
            state.inputText = s
            state.expressionText = s
            state.entering = true
            state.justEvaluated = false
            limitFractionDigits(maxDigits: 8)
            return
        }
        
        if !state.entering {
            state.inputText = s
            state.expressionText.append(s)
            state.entering = true
            limitFractionDigits(maxDigits: 8)
            return
        }
        
        if state.inputText == "0" && s != decSep {
            state.inputText = s
            // Заменяем последний "0" в expressionText на новую цифру, если он действительно последний
            // (не часть числа типа "10" или "20")
            if !state.expressionText.isEmpty {
                let lastChar = state.expressionText.last!
                // Если последний символ - "0" и перед ним оператор или начало выражения
                if lastChar == "0" {
                    // Проверяем, что это действительно отдельный "0", а не часть числа
                    let beforeLast = state.expressionText.count > 1
                    ? state.expressionText[state.expressionText.index(state.expressionText.endIndex, offsetBy: -2)]
                    : nil
                    let operators: Set<Character> = ["+", "-", "*", "/", "="]
                    let shouldReplaceZero = beforeLast.map { operators.contains($0) } ?? true
                    if shouldReplaceZero {
                        state.expressionText.removeLast()
                        state.expressionText.append(s)
                    } else {
                        // Это часть числа, просто добавляем
                        state.expressionText.append(s)
                    }
                } else {
                    state.expressionText.append(s)
                }
            } else {
                state.expressionText = s
            }
        } else {
            state.inputText.append(s)
            state.expressionText.append(s)
        }
        limitFractionDigits(maxDigits: 8)
    }
    
    private func appendComma() {
        if !state.entering || state.justEvaluated {
            state.inputText = "0\(decSep)"
            state.expressionText = state.inputText
            state.entering = true
            state.justEvaluated = false
            return
        }
        if state.inputText.contains(decSep) || state.inputText.contains(otherSeparator(decSep)) { return }
        if state.inputText.isEmpty { state.inputText = "0" }
        state.inputText.append(decSep)
        state.expressionText.append(decSep)
    }
    
    private func otherSeparator(_ sep: String) -> String {
        sep == "," ? "." : ","
    }
    
    private func percent() {
        guard let v = parseAmount(state.inputText) else { return }
        let p = v / 100.0
        state.inputText = formatPlain(p, maxFrac: 8).replacingOccurrences(of: " ", with: "")
        state.entering = true
        state.justEvaluated = false
    }
    
    private func op(_ symbol: String) {
        let current = parseAmount(state.inputText) ?? 0
        if let op = state.pendingOp, let acc = state.accumulator, state.entering {
            let res = apply(op: op, lhs: acc, rhs: current)
            state.accumulator = res
            state.inputText = formatPlain(res, maxFrac: 8).replacingOccurrences(of: " ", with: "")
        } else {
            state.accumulator = current
        }
        state.pendingOp = symbol
        if state.entering {
            state.expressionText.append(symbol)
        } else {
            if let last = state.expressionText.last, ["+", "-", "*", "/"].contains(String(last)) {
                state.expressionText.removeLast()
                state.expressionText.append(symbol)
            }
        }
        state.entering = false
        state.justEvaluated = false
    }
    
    private func equal() {
        let rhs = parseAmount(state.inputText) ?? 0
        if let op = state.pendingOp, let acc = state.accumulator {
            let res = apply(op: op, lhs: acc, rhs: rhs)
            let resultText = formatPlain(res, maxFrac: 8).replacingOccurrences(of: " ", with: "")
            let rhsText = state.inputText
            let lhsText = formatPlain(acc, maxFrac: 8).replacingOccurrences(of: " ", with: "")
            state.expressionText = lhsText + op + rhsText + "=" + resultText
            state.inputText = resultText
            state.accumulator = res
            state.pendingOp = nil
            state.entering = false
            state.justEvaluated = true
        } else {
            let resultText = formatPlain(rhs, maxFrac: 8).replacingOccurrences(of: " ", with: "")
            state.expressionText = state.inputText + "=" + resultText
            state.inputText = resultText
            state.entering = false
            state.justEvaluated = true
        }
    }
    
    private func apply(op: String, lhs: Double, rhs: Double) -> Double {
        switch op {
        case "+": return lhs + rhs
        case "-": return lhs - rhs
        case "*": return lhs * rhs
        case "/": return rhs == 0 ? lhs : lhs / rhs
        default: return rhs
        }
    }
    
    private func limitFractionDigits(maxDigits: Int) {
        let s = state.inputText
        let sep = decSep
        if let range = s.range(of: sep) {
            let frac = s[range.upperBound...]
            if frac.count > maxDigits {
                state.inputText = String(s.prefix(s.count - (frac.count - maxDigits)))
            }
        }
    }
    
    // MARK: - Formatting
    
    private func parseAmount(_ s: String) -> Double? {
        let normalized = s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        return Double(normalized)
    }

    private func formatInputForDisplay(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "0" }

        let isNegative = trimmed.hasPrefix("-")
        let signless = isNegative ? String(trimmed.dropFirst()) : trimmed
        let separatorIndex = signless.firstIndex(where: { $0 == "," || $0 == "." })

        let integerPartRaw: String
        let fractionalPartRaw: String?
        let hasTrailingSeparator: Bool

        if let separatorIndex {
            integerPartRaw = String(signless[..<separatorIndex])
            let fractionStart = signless.index(after: separatorIndex)
            fractionalPartRaw = String(signless[fractionStart...])
            hasTrailingSeparator = fractionStart == signless.endIndex
        } else {
            integerPartRaw = signless
            fractionalPartRaw = nil
            hasTrailingSeparator = false
        }

        let safeInteger = integerPartRaw.isEmpty ? "0" : integerPartRaw
        let groupedInteger = groupedThousands(safeInteger)

        var output = isNegative ? "-\(groupedInteger)" : groupedInteger
        if hasTrailingSeparator {
            output += decSep
            return output
        }

        if let fractionalPartRaw {
            output += decSep + fractionalPartRaw
        }

        return output
    }

    private func groupedThousands(_ digits: String) -> String {
        guard !digits.isEmpty else { return "0" }
        guard digits.allSatisfy(\.isNumber) else { return digits }

        var result: [Character] = []
        result.reserveCapacity(digits.count + digits.count / 3)

        for (idx, char) in digits.reversed().enumerated() {
            if idx > 0 && idx % 3 == 0 {
                result.append(" ")
            }
            result.append(char)
        }
        return String(result.reversed())
    }
    
    private func formatPlain(_ value: Double, maxFrac: Int = 2) -> String {
        ConverterL10n.decimalNumberString(from: value, maxFractionDigits: maxFrac)
    }
    
    // MARK: - Network

    /// Стрим изменений сетевой доступности. true = есть соединение, false = нет.
    /// Lifecycle мониторинга привязан к lifetime стрима (отменяется когда Task отменяется).
    nonisolated var networkStatusStream: AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "millio.converter.network", qos: .utility)
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            monitor.start(queue: queue)
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }

    func fetchRates(haptic: Bool = false, force: Bool = false) async {
        if state.isFetchingRates { return }

        let requiredCrypto = requiredCryptoCodes()
        let requestedCodes = requestedRefreshCodes()
        let needsCryptoBackfill = hasMissingCryptoRates(for: requiredCrypto)
        
        let now = Date().timeIntervalSince1970
        if !force, state.allRates.count > 1, storedLastRatesTS > 0, (now - storedLastRatesTS) < 6 * 3600, !needsCryptoBackfill {
            return
        }
        
        state.isFetchingRates = true
        defer { state.isFetchingRates = false }

        if !force, state.allRates.count > 1, storedLastRatesTS > 0, (now - storedLastRatesTS) < 6 * 3600, needsCryptoBackfill {
            let updated = await refreshCryptoRates(requiredCodes: requiredCrypto)
            if updated {
                storedCachedRates = state.allRates
                syncWidgetConverterSnapshot()
            }
            presentRefreshIssueIfNeeded(for: missingRequestedCodes(from: requestedCodes))
            return
        }
        
        await currencyService.forceRefreshRates()
        guard let snapshot = currencyService.currentRateSnapshot(), snapshot.rates.count > 1 else {
            state.isOffline = true
            presentRefreshIssueIfNeeded(
                for: requestedCodes,
                fallback: errorRefreshMessage(for: requestedCodes, error: URLError(.notConnectedToInternet))
            )
            return
        }

        state.allRates = snapshot.rates
        _ = await refreshCryptoRates(requiredCodes: requiredCrypto)
        storedCachedRates = state.allRates
        // Для UI и виджета важнее момент фактической загрузки на устройстве,
        // чем дата/время публикации у провайдера. Иначе часть источников
        // показывает "синтетическое" или неочевидное для пользователя время.
        storedLastRatesTS = snapshot.fetchedAt
        state.isOffline = false

        // Фильтруем выбранные валюты, оставляя только те, что есть в новом источнике
        filterSelectedCurrenciesToAvailable()
        syncWidgetConverterSnapshot()
        presentRefreshIssueIfNeeded(for: missingRequestedCodes(from: requestedCodes))
    }
    
    // MARK: - Share Helpers
    
    func getShareData(now: Date = Date()) -> (rows: [ShareRowModel], dateString: String, highlightedCode: String) {
        let rows: [ShareRowModel] = state.selectedCurrencies.map { code in
            ShareRowModel(
                flag: "", // Флаги больше не используются, используется Image("flag")
                code: code,
                value: displayValue(for: code)
            )
        }

        let dateStr = ConverterL10n.shareTimestamp(for: now)

        return (rows, dateStr, state.activeCode)
    }
    
    func setShareImage(_ image: UIImage?) {
        state.shareImage = image
    }

    private func appendShareHistoryEntry(imageData: Data?, shareTitle: String, note: String?) {
        let imageFileName = saveHistoryImage(data: imageData)
        let entry = ConverterShareHistoryItem(
            id: UUID(),
            createdAt: Date(),
            activeCode: state.activeCode,
            inputText: canonicalInputText(state.inputText),
            selectedCodes: state.selectedCurrencies,
            imageFileName: imageFileName,
            shareTitle: shareTitle,
            note: note
        )
        state.shareHistory.insert(entry, at: 0)
        if state.shareHistory.count > maxShareHistoryItems {
            let overflow = state.shareHistory.dropFirst(maxShareHistoryItems)
            for item in overflow {
                deleteHistoryImage(fileName: item.imageFileName)
            }
            state.shareHistory = Array(state.shareHistory.prefix(maxShareHistoryItems))
        }
        persistShareHistory()
    }

    private func loadShareHistory() -> [ConverterShareHistoryItem] {
        guard let data = storedShareHistoryData else { return [] }
        do {
            return try JSONDecoder().decode([ConverterShareHistoryItem].self, from: data)
        } catch {
            return []
        }
    }

    private func persistShareHistory() {
        do {
            storedShareHistoryData = try JSONEncoder().encode(state.shareHistory)
        } catch {
            storedShareHistoryData = nil
        }
    }

    private func saveHistoryImage(data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let fileName = "share_\(UUID().uuidString).jpg"
        let url = historyImagesDirectoryURL().appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(
                at: historyImagesDirectoryURL(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private func deleteHistoryImage(fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        let url = historyImagesDirectoryURL().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private func historyImagesDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ConverterShareHistory", isDirectory: true)
    }

    private func canonicalInputText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }
    
    
    // MARK: - Helpers
    
    var allAvailableCodes: [String] {
        // Фиат — из текущего источника. Крипта — из поддерживаемого списка.
        let fiatCodes = Set(state.allRates.keys).union(["USD"])
        let allCodes = CurrencySelectionSupport.allCodes(includeCrypto: true)
        return allCodes.filter { code in
            let uppercased = code.uppercased()
            return fiatCodes.contains(uppercased) || supportedCryptoCodes.contains(uppercased)
        }
    }
    
    var filteredCodes: [String] {
        let q = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allAvailableCodes }
        return allAvailableCodes.filter { code in
            let codeL = code.lowercased()
            let nameRu = CurrencySelectionSupport.nameRu(for: code)?.lowercased() ?? ""
            let _ = CurrencySelectionSupport.nameEn(for: code)?.lowercased() ?? ""
            let aliases = CurrencySelectionSupport.aliases[code]?.map { $0.lowercased() } ?? []
            let aliasHit = aliases.contains(where: { $0.contains(q) })
            return codeL.contains(q) || nameRu.contains(q) || aliasHit
        }
    }
    
    var ratesStale: Bool {
        guard storedLastRatesTS > 0 else { return true }
        return Date().timeIntervalSince1970 - storedLastRatesTS > 12 * 3600
    }
    
    var connectivityIconName: String? {
        guard state.showOfflineBadge else { return nil }
        if state.isFetchingRates { return "arrow.triangle.2.circlepath" }
        if state.isOffline { return "wifi.slash" }
        if ratesStale { return "wifi.exclamationmark" }
        return nil
    }
    
    var lastUpdatedText: String {
        guard storedLastRatesTS > 0 else { return "—" }
        return ConverterL10n.shareTimestamp(for: Date(timeIntervalSince1970: storedLastRatesTS))
    }
    
    var canRemoveCurrency: Bool {
        state.selectedCurrencies.count > 1
    }
    
    var canAddCurrency: Bool {
        state.selectedCurrencies.count < maxCurrencies
    }

    func enforceCryptoAccess(allowCrypto: Bool) {
        guard !allowCrypto else { return }

        state.selectedCurrencies = state.selectedCurrencies.filter { !CurrencySelectionSupport.isCrypto($0) }
        if state.selectedCurrencies.isEmpty {
            state.selectedCurrencies = ["USD", "EUR", "RUB"].filter { state.allRates[$0] != nil || $0 == "USD" }
            if state.selectedCurrencies.isEmpty {
                state.selectedCurrencies = ["USD"]
            }
        }

        if CurrencySelectionSupport.isCrypto(state.activeCode) || !state.selectedCurrencies.contains(state.activeCode) {
            state.activeCode = state.selectedCurrencies.first ?? "USD"
            storedActive = state.activeCode
            mirrorToICloud(key: "conv_active_code", value: state.activeCode)
        }

        persistSelected()
        syncWidgetConverterSnapshot()
    }
    
    private func persistInputIfNeeded(previousInput: String) {
        guard state.inputText != previousInput else { return }
        storedInput = state.inputText
        mirrorToICloud(key: "conv_input_text", value: state.inputText)
    }
    
    private func syncWidgetConverterSnapshot() {
        CurrencyWidgetSyncService.setString(
            state.selectedCurrencies.joined(separator: ","),
            forKey: CurrencyWidgetShared.Keys.selectedCodes
        )
        CurrencyWidgetSyncService.setString(state.activeCode, forKey: CurrencyWidgetShared.Keys.activeCode)
        CurrencyWidgetSyncService.setString(state.inputText, forKey: CurrencyWidgetShared.Keys.inputText)
        // rateSource не синкается здесь — виджет получает его через bootstrapFromStandardDefaults (preferred_rate_source)
        CurrencyWidgetSyncService.setRates(state.allRates, forSource: state.rateSource.rawValue)
        
        if storedLastRatesTS > 0 {
            CurrencyWidgetSyncService.setLastRatesTimestamp(storedLastRatesTS, forSource: state.rateSource.rawValue)
        }
    }

    private func requiredCryptoCodes() -> [String] {
        Set((state.selectedCurrencies + [state.activeCode]).map { $0.uppercased() })
            .filter { supportedCryptoCodes.contains($0) }
            .sorted()
    }

    private func requestedRefreshCodes() -> [String] {
        Set((state.selectedCurrencies + [state.activeCode]).map { $0.uppercased() })
            .filter { !$0.isEmpty && $0 != "USD" }
            .sorted()
    }

    private func missingRequestedCodes(from requestedCodes: [String]) -> [String] {
        requestedCodes.filter { state.allRates[$0] == nil }
    }

    private func hasMissingCryptoRates(for codes: [String]) -> Bool {
        codes.contains { (state.allRates[$0] ?? 0) <= 0 }
    }

    func dismissToast() {
        state.showToast = false
        state.toastMessage = nil
    }

    private func presentRefreshIssueIfNeeded(for codes: [String], fallback: String? = nil) {
        if let message = refreshIssueMessage(for: codes) ?? fallback {
            state.toastMessage = message
            state.showToast = true
        } else {
            dismissToast()
        }
    }

    private func refreshIssueMessage(for codes: [String]) -> String? {
        guard !codes.isEmpty else { return nil }
        let prefix = localizedRefreshIssuePrefix()
        return "\(prefix): \(codes.joined(separator: ", "))"
    }

    private func errorRefreshMessage(for codes: [String], error: Error) -> String {
        if !codes.isEmpty {
            return refreshIssueMessage(for: codes) ?? localizedRefreshFallbackMessage()
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return ConverterL10n.noInternetError
            case .timedOut:
                return ConverterL10n.timeoutError
            case .badServerResponse:
                return ConverterL10n.serverError(source: state.rateSource.title)
            case .cannotParseResponse:
                return ConverterL10n.parseError(source: state.rateSource.title)
            default:
                return localizedRefreshFallbackMessage()
            }
        }

        return localizedRefreshFallbackMessage()
    }

    private func localizedRefreshIssuePrefix() -> String {
        ConverterL10n.genericUpdateError
    }

    private func localizedRefreshFallbackMessage() -> String {
        ConverterL10n.genericUpdateError
    }

    /// Догружает crypto-курсы в формате "1 USD = X CRYPTO" и мержит в текущий словарь.
    @discardableResult
    private func refreshCryptoRates(requiredCodes: [String]) async -> Bool {
        let codes = requiredCodes.filter { supportedCryptoCodes.contains($0) }
        guard !codes.isEmpty else { return false }

        let ids = codes.compactMap { cryptoCodeToId[$0] }
        guard !ids.isEmpty else { return false }

        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price") else {
            return false
        }
        components.queryItems = [
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        guard let url = components.url else { return false }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] ?? [:]
            var updates: [String: Double] = [:]

            for code in codes {
                guard let id = cryptoCodeToId[code], let usdPrice = json[id]?["usd"], usdPrice > 0 else {
                    continue
                }
                updates[code] = 1.0 / usdPrice
            }

            guard !updates.isEmpty else { return false }
            for (code, rate) in updates {
                state.allRates[code] = rate
            }
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Response Models

private struct ERAPIResponse: Decodable {
    let result: String
    let time_last_update_unix: Int
    let base_code: String
    let rates: [String: Double]
}

private struct FrankfurterResponse: Decodable {
    let rates: [String: Double]
    let base: String?
    let date: String?
}

// MARK: - iCloud KVS mirror

private func mirrorToICloud(key: String, value: String) {
    #if os(iOS)
    // Опциональная синхронизация настроек с iCloud Key-Value Storage
    // Требует entitlement: com.apple.developer.ubiquity-kvstore-identifier
    let kvs = NSUbiquitousKeyValueStore.default
    if kvs.string(forKey: key) != value {
        kvs.set(value, forKey: key)
        kvs.synchronize()
    }
    #endif
}

#if os(iOS)
private func converterSafeAreaBottom() -> CGFloat {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
        if let window = scene.windows.first(where: { $0.isKeyWindow }) {
            return window.safeAreaInsets.bottom
        }
    }
    return scenes.first?.windows.first?.safeAreaInsets.bottom ?? 0
}
#endif
