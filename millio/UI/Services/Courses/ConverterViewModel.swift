//
//  ConverterViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import Combine
#if os(iOS)
import UIKit
import AudioToolbox
#endif

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
    var rateSource: RateSource = .erapi
    var showOfflineBadge: Bool = true
    var hapticsEnabled: Bool = true
    var isOffline: Bool = false
    var isFetchingRates: Bool = false
    var fractionDigits: Int = 4
    
    // Калькулятор
    var accumulator: Double? = nil
    var pendingOp: String? = nil
    var entering: Bool = true
    var justEvaluated: Bool = false
    var expressionText: String = ""
    var calcModeOn: Bool = false
    
    // Share
    var shareImage: UIImage? = nil
    var showShareSheet: Bool = false
    
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
    
    private var selectedCodesRaw: String {
        get { defaults.string(forKey: "conv_selected_codes") ?? "RUB,USD,EUR,TRY,GBP,KZT" }
        set { defaults.set(newValue, forKey: "conv_selected_codes") }
    }
    
    private var storedActive: String {
        get { defaults.string(forKey: "conv_active_code") ?? "TRY" }
        set { defaults.set(newValue, forKey: "conv_active_code") }
    }
    
    private var storedInput: String {
        get { defaults.string(forKey: "conv_input_text") ?? "1200" }
        set { defaults.set(newValue, forKey: "conv_input_text") }
    }
    
    private var storedFractionDigits: Int {
        get { defaults.integer(forKey: "conv_fraction_digits") == 0 ? 4 : defaults.integer(forKey: "conv_fraction_digits") }
        set { defaults.set(newValue, forKey: "conv_fraction_digits") }
    }
    
    private var storedRateSource: String {
        get { defaults.string(forKey: "conv_rate_source") ?? "erapi" }
        set { defaults.set(newValue, forKey: "conv_rate_source") }
    }
    
    private var storedShowOfflineBadge: Bool {
        get { defaults.object(forKey: "conv_show_offline_badge") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "conv_show_offline_badge") }
    }
    
    private var storedHapticsEnabled: Bool {
        get { defaults.object(forKey: "conv_haptics_enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "conv_haptics_enabled") }
    }
    
    private var storedLastRatesTS: Double {
        get {
            let key = "conv_last_rates_ts_\(state.rateSource.rawValue)"
            return defaults.double(forKey: key)
        }
        set {
            let key = "conv_last_rates_ts_\(state.rateSource.rawValue)"
            defaults.set(newValue, forKey: key)
        }
    }
    
    private let maxCurrencies: Int = 6
    
    private var decSep: String { Locale.current.decimalSeparator ?? "," }
    
    var currentFractionDigits: Int {
        max(0, min(8, storedFractionDigits))
    }
    
    init() {
        onAppearInit()
        // Проверяем валюты после инициализации, если курсы уже загружены
        if state.allRates.count > 1 {
            filterSelectedCurrenciesToAvailable()
        }
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
    }
    
    func handle(_ action: Action) {
        switch action {
        case .selectCurrency(let code):
            state.activeCode = code
            storedActive = code
            mirrorToICloud(key: "conv_active_code", value: code)
            state.calcModeOn = false
            
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
            storedInput = text
            mirrorToICloud(key: "conv_input_text", value: text)
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
            state.rateSource = source
            storedRateSource = source.rawValue
            mirrorToICloud(key: "conv_rate_source", value: source.rawValue)
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
            state.showShareSheet = true
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
        
        state.rateSource = RateSource(rawValue: storedRateSource) ?? .erapi
        state.showOfflineBadge = storedShowOfflineBadge
        state.hapticsEnabled = storedHapticsEnabled
        if state.expressionText.isEmpty {
            state.expressionText = state.inputText
        }
        
        // Синхронизация состояния
        state.fractionDigits = storedFractionDigits
    }
    
    // MARK: - Currency Management
    
    func displayValue(for code: String) -> String {
        guard let input = parseAmount(state.inputText) else { return "0" }
        let amountInCode = convert(amount: input, from: state.activeCode, to: code)
        return formatPlain(amountInCode, maxFrac: currentFractionDigits)
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
        let availableCodes = Set(state.allRates.keys).union(["USD"])
        
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
        if let idx = state.replaceIndex, state.selectedCurrencies.indices.contains(idx) {
            state.selectedCurrencies[idx] = code
        } else {
            guard state.selectedCurrencies.count < maxCurrencies else { return }
            if !state.selectedCurrencies.contains(code) {
                state.selectedCurrencies.append(code)
            }
        }
        if !state.selectedCurrencies.contains(state.activeCode) {
            state.activeCode = state.selectedCurrencies.first ?? "USD"
        }
        persistSelected()
        state.showPicker = false
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
                    let beforeLast = state.expressionText.count > 1 ? state.expressionText[state.expressionText.index(state.expressionText.endIndex, offsetBy: -2)] : nil
                    if beforeLast == nil || ["+", "-", "*", "/", "="].contains(String(beforeLast!)) {
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
    
    private func formatPlain(_ value: Double, maxFrac: Int = 2) -> String {
        struct F {
            static var nf: NumberFormatter = {
                let nf = NumberFormatter()
                nf.numberStyle = .decimal
                nf.usesGroupingSeparator = true
                nf.groupingSeparator = " "
                nf.minimumFractionDigits = 0
                nf.maximumFractionDigits = 2
                nf.locale = Locale.current
                return nf
            }()
        }
        F.nf.decimalSeparator = Locale.current.decimalSeparator ?? ","
        F.nf.maximumFractionDigits = maxFrac
        return F.nf.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFrac)f", value)
    }
    
    // MARK: - Network
    
    func fetchRates(haptic: Bool = false, force: Bool = false) async {
        if state.isFetchingRates { return }
        
        let now = Date().timeIntervalSince1970
        if !force, state.allRates.count > 1, storedLastRatesTS > 0, (now - storedLastRatesTS) < 6 * 3600 {
            return
        }
        
        state.isFetchingRates = true
        defer { state.isFetchingRates = false }
        
        do {
            let url: URL
            switch state.rateSource {
            case .erapi:
                url = URL(string: "https://open.er-api.com/v6/latest/USD")!
            case .frankfurter:
                url = URL(string: "https://api.frankfurter.app/latest?from=USD")!
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            var rates: [String: Double] = [:]
            var updateTS: Double = now
            
            switch state.rateSource {
            case .erapi:
                let decoded = try JSONDecoder().decode(ERAPIResponse.self, from: data)
                guard decoded.result == "success" else { throw URLError(.cannotParseResponse) }
                rates = decoded.rates
                updateTS = TimeInterval(decoded.time_last_update_unix)
                
            case .frankfurter:
                let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
                // Frankfurter использует EUR как базовую валюту, нужно конвертировать в USD
                let eurRates = decoded.rates
                if let eurToUsd = eurRates["USD"] {
                    // Конвертируем все курсы из EUR в USD
                    for (code, eurRate) in eurRates {
                        if code != "USD" {
                            // 1 USD = (1 / eurToUsd) * eurRate EUR = eurRate / eurToUsd
                            rates[code] = eurRate / eurToUsd
                        }
                    }
                } else {
                    // Если нет курса EUR/USD, используем курсы как есть (но это не должно произойти)
                    rates = eurRates
                }
                // Парсим дату из ответа (формат YYYY-MM-DD)
                if let dateStr = decoded.date {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    df.locale = Locale(identifier: "en_US_POSIX")
                    df.timeZone = TimeZone(secondsFromGMT: 0) // UTC
                    if let date = df.date(from: dateStr) {
                        // Устанавливаем время на 16:00 CET (15:00 UTC) - время обновления Frankfurter
                        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                        components.hour = 15
                        components.minute = 0
                        components.timeZone = TimeZone(secondsFromGMT: 0)
                        if let dateWithTime = Calendar.current.date(from: components) {
                            updateTS = dateWithTime.timeIntervalSince1970
                        } else {
                            updateTS = date.timeIntervalSince1970
                        }
                    }
                }
            }
            
            rates["USD"] = 1.0
            rates = rates.filter { !$0.key.isEmpty && $0.value > 0 }
            
            if rates.isEmpty { throw URLError(.cannotParseResponse) }
            
            state.allRates = rates
            storedLastRatesTS = updateTS
            state.isOffline = false
            
            // Фильтруем выбранные валюты, оставляя только те, что есть в новом источнике
            filterSelectedCurrenciesToAvailable()
            
            // Тактильный отклик теперь только в UI при нажатии на кнопку
        } catch {
            state.isOffline = true
            
            // Показываем ошибку в тостере
            let errorMessage: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    errorMessage = "Нет подключения к интернету"
                case .timedOut:
                    errorMessage = "Превышено время ожидания"
                case .badServerResponse:
                    errorMessage = "Ошибка сервера \(state.rateSource.title)"
                case .cannotParseResponse:
                    errorMessage = "Не удалось обработать ответ от \(state.rateSource.title)"
                default:
                    errorMessage = "Ошибка при обновлении курсов"
                }
            } else {
                errorMessage = "Ошибка при обновлении курсов"
            }
            
            state.toastMessage = errorMessage
            state.showToast = true
            
            // Автоматически скрываем тостер через 3 секунды
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                state.showToast = false
                state.toastMessage = nil
            }
        }
    }
    
    // MARK: - Share Helpers
    
    func getShareData() -> (rows: [ShareRowModel], dateString: String, highlightedCode: String) {
        let rows: [ShareRowModel] = state.selectedCurrencies.map { code in
            ShareRowModel(
                flag: "", // Флаги больше не используются, используется Image("flag")
                code: code,
                value: displayValue(for: code)
            )
        }
        
        let df = DateFormatter()
        df.locale = Locale(identifier: Locale.current.identifier)
        df.dateFormat = "dd MMM • HH:mm"
        let dateStr = df.string(from: Date())
        
        return (rows, dateStr, state.activeCode)
    }
    
    func setShareImage(_ image: UIImage?) {
        state.shareImage = image
    }
    
    
    // MARK: - Helpers
    
    var allAvailableCodes: [String] {
        // Фильтруем по доступным валютам в текущем источнике
        let availableCodes = Set(state.allRates.keys).union(["USD"])
        let allCodes = CurrencySelectionSupport.allCodes(includeCrypto: true)
        return allCodes.filter { availableCodes.contains($0.uppercased()) }
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
        let df = DateFormatter()
        df.locale = Locale(identifier: Locale.current.identifier)
        df.dateFormat = "dd MMM • HH:mm"
        return df.string(from: Date(timeIntervalSince1970: storedLastRatesTS))
    }
    
    var canRemoveCurrency: Bool {
        state.selectedCurrencies.count > 1
    }
    
    var canAddCurrency: Bool {
        state.selectedCurrencies.count < maxCurrencies
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
