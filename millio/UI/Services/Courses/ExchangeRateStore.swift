import Foundation
import SwiftUI
import Combine

// MARK: - ExchangeRateStore (FIAT + CRYPTO)
// allRates хранит курсы к USD в формате: "RUB": 100 означает 1 USD = 100 RUB
// Для крипты храним так же: "BTC": 0.000022 означает 1 USD = 0.000022 BTC (то есть BTC/USD инвертируем)

@MainActor
final class ExchangeRateStore: ObservableObject {

    // Полный словарь курсов к USD: "RUB": 100.12 означает 1 USD = 100.12 RUB
    @Published private(set) var allRates: [String: Double] = ["USD": 1.0]

    // Флаг готовности: true, когда в словаре есть валидные курсы (минимум USD=1)
    @Published private(set) var ratesReady: Bool = true

    // Совместимость: курс USD→RUB (RUB за 1 USD)
    @Published private(set) var usdToRub: Double?

    @AppStorage("rates_last_update_ts") private var lastUpdateTS: Double = 0
    @AppStorage("rates_usd_to_rub") private var storedUsdToRub: Double = 0

    // MARK: - Crypto mapping (CoinGecko IDs)
    // Добавляй/убирай монеты как нужно
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

    init() {
        // восстановим сохранённый курс USD→RUB
        if storedUsdToRub > 0 {
            usdToRub = storedUsdToRub
            allRates["RUB"] = storedUsdToRub
        }
        // гарантируем, что USD всегда 1
        allRates["USD"] = 1.0
        ratesReady = !allRates.isEmpty && (allRates["USD"] ?? 0) == 1.0
    }

    // MARK: - Public API

    // Поддержка старого вызова: обеспечит наличие курса USD→RUB
    func ensureLatestUSDRate() async {
        if usdToRub == nil || usdToRub == 0 {
            await refreshRates()
        } else {
            let now = Date().timeIntervalSince1970
            if now - lastUpdateTS > 12 * 3600 {
                await refreshRates()
            }
        }
    }

    // Убедиться, что курсы актуальны. requiredCodes может содержать и крипту.
    func ensureLatestRates(requiredCodes: [String] = []) async {
        let defaults = ["USD", "RUB", "EUR", "TRY", "CNY", "GBP", "KZT", "JPY"]
        let need = (requiredCodes.isEmpty ? defaults : requiredCodes).map { $0.uppercased() }

        let now = Date().timeIntervalSince1970
        let needsInitialLoad = allRates.count <= 1
        let isStale = (now - lastUpdateTS) > 12 * 3600

        if needsInitialLoad || isStale || !hasAll(need) {
            // 1) Фиат
            await refreshRates()

            // 2) Крипта по потребности
            await refreshCryptoRates(requiredCodes: need)

            // Повторная попытка, если чего-то не хватает
            if !hasAll(need) {
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                await refreshRates()
                await refreshCryptoRates(requiredCodes: need)
            }
        }

        sanitize()
        ratesReady = !allRates.isEmpty && (allRates["USD"] ?? 0) == 1.0
    }

    // Проверка наличия конкретного кода
    func hasRate(_ code: String) -> Bool {
        let c = code.uppercased()
        return c == "USD" ? true : (allRates[c] ?? 0) > 0
    }

    private func hasAll(_ codes: [String]) -> Bool {
        for c in codes {
            if !hasRate(c) { return false }
        }
        return true
    }

    // Курс: сколько единиц 'to' за 1 единицу 'from'
    func rate(from: String, to: String) -> Double? {
        let f = from.uppercased()
        let t = to.uppercased()
        if f == t { return 1 }

        // считаем через USD-пивот
        let rFromUSD: Double? = (f == "USD") ? 1.0 : allRates[f]
        let rToUSD: Double? = (t == "USD") ? 1.0 : allRates[t]
        guard let rFrom = rFromUSD, let rTo = rToUSD, rFrom > 0 else { return nil }

        // 1 FROM = rTo / rFrom TO
        return rTo / rFrom
    }

    // Удобный перегруз для MonetaCurrency (если тип есть в проекте)
    func rate(from: MonetaCurrency, to: MonetaCurrency) -> Double? {
        rate(from: from.rawValue, to: to.rawValue)
    }

    // MARK: - Server refresh (FIAT)

    func refreshRates() async {
        do {
            let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            struct ERAPIResponse: Decodable {
                let result: String
                let rates: [String: Double]
                let time_last_update_unix: Int
            }

            let decoded = try JSONDecoder().decode(ERAPIResponse.self, from: data)
            guard decoded.result == "success" else {
                throw URLError(.cannotParseResponse)
            }

            var rates = decoded.rates
            rates["USD"] = 1.0
            rates = rates.filter { !$0.key.isEmpty && $0.value > 0 }

            if rates.isEmpty {
                sanitize()
                return
            }

            // Обновляем фиат-курсы
            for (k, v) in rates {
                allRates[k.uppercased()] = v
            }

            // Совместимость: RUB для старого API
            if let rub = allRates["RUB"], rub > 0 {
                usdToRub = rub
                storedUsdToRub = rub
            }

            lastUpdateTS = TimeInterval(decoded.time_last_update_unix)
            ratesReady = !allRates.isEmpty && (allRates["USD"] ?? 0) == 1.0
        } catch {
            sanitize()
        }
    }

    // MARK: - Crypto refresh (CoinGecko)

    private func isCrypto(_ code: String) -> Bool {
        cryptoCodeToId[code.uppercased()] != nil
    }

    /// Загружает цены crypto в USD и кладёт в allRates как "1 USD = X CRYPTO"
    private func refreshCryptoRates(requiredCodes: [String]) async {
        let codes = requiredCodes.map { $0.uppercased() }.filter(isCrypto)
        guard !codes.isEmpty else { return }

        let ids = codes.compactMap { cryptoCodeToId[$0] }
        guard !ids.isEmpty else { return }

        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        comps.queryItems = [
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        guard let url = comps.url else { return }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }

            // ответ вида: { "bitcoin": { "usd": 45000 }, "ethereum": { "usd": 2400 } }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] ?? [:]

            var updates: [String: Double] = [:]
            for code in codes {
                guard let id = cryptoCodeToId[code],
                      let usdPrice = json[id]?["usd"],
                      usdPrice > 0 else { continue }

                // 1 USD = (1 / usdPrice) coin
                updates[code] = 1.0 / usdPrice
            }

            // Вливаем в общий словарь (не затираем фиат)
            if !updates.isEmpty {
                for (k, v) in updates { allRates[k] = v }
            }
        } catch {
            // молча оставляем старые значения
        }
    }

    // MARK: - Sanitize

    private func sanitize() {
        if allRates.isEmpty { allRates = ["USD": 1.0] }
        allRates["USD"] = 1.0

        if let rub = allRates["RUB"], rub > 0 {
            usdToRub = rub
            storedUsdToRub = rub
        }
        ratesReady = !allRates.isEmpty && (allRates["USD"] ?? 0) == 1.0
    }
}

// MARK: - Service adapter (если нужно для твоей архитектуры)

protocol ExchangeRateService: AnyObject {
    // Возвращает курс: сколько TO за 1 единицу FROM на дату date
    func getRate(from: String, to: String, date: Date) async -> Double?
}

@MainActor
final class ExchangeRateStoreServiceAdapter: ExchangeRateService {
    private let store: ExchangeRateStore
    init(store: ExchangeRateStore) { self.store = store }

    func getRate(from: String, to: String, date: Date) async -> Double? {
        // 1) Пытаемся получить курс из общего словаря (фиат+крипта)
        if let r = store.rate(from: from, to: to) {
            return r
        }

        // 2) Фоллбэк для старой логики USD<->RUB
        if from.uppercased() == "USD", to.uppercased() == "RUB" {
            if store.usdToRub == nil || store.usdToRub == 0 {
                await store.ensureLatestUSDRate()
            }
            return store.usdToRub
        }

        if from.uppercased() == "RUB", to.uppercased() == "USD" {
            if store.usdToRub == nil || store.usdToRub == 0 {
                await store.ensureLatestUSDRate()
            }
            guard let r = store.usdToRub, r > 0 else { return nil }
            return 1.0 / r
        }

        return from.uppercased() == to.uppercased() ? 1 : nil
    }
}
