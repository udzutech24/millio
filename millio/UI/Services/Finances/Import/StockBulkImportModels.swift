import Foundation

enum StockBulkImportNumberParser {
    static func parse(_ rawValue: String) -> Double? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }
}

struct StockBulkImportCandidate: Identifiable, Equatable, Hashable, Sendable {
    let symbol: String
    let market: String?
    let displayName: String
    let currency: String
    let providerRaw: String?

    var id: String {
        "\(normalizedMarket ?? "")|\(normalizedSymbol)"
    }

    var normalizedSymbol: String {
        Self.canonicalTicker(from: symbol)
    }

    var normalizedMarket: String? {
        StockBulkImportMarketNormalizer.normalize(market)
    }

    var storedSymbol: String {
        guard let normalizedMarket, !normalizedMarket.isEmpty else {
            return normalizedSymbol
        }
        return "\(normalizedMarket):\(normalizedSymbol)"
    }

    /// Символ для market API. Импорт хранит legacy-формат `MARKET:TICKER`,
    /// но backend для США ожидает `TICKER.US`, а для основных US бирж — просто тикер.
    var quoteLookupSymbol: String {
        quoteLookupSymbols.first ?? normalizedSymbol
    }

    /// Backend market API исторически принимает разные формы одного и того же US-инструмента.
    /// Не делаем вид, что формат один: пробуем безопасные fallback-варианты по приоритету.
    var quoteLookupSymbols: [String] {
        guard let normalizedMarket, !normalizedMarket.isEmpty else {
            return [normalizedSymbol]
        }

        switch normalizedMarket {
        case "US":
            return uniqueQuoteSymbols([
                "\(normalizedSymbol).US",
                normalizedSymbol,
                storedSymbol
            ])
        case "NASDAQ", "NYSE", "AMEX", "BATS", "IEX":
            return uniqueQuoteSymbols([
                normalizedSymbol,
                "\(normalizedSymbol).US",
                storedSymbol
            ])
        default:
            return uniqueQuoteSymbols([
                storedSymbol,
                normalizedSymbol
            ])
        }
    }

    /// Ключ идентичности нужен для merge с уже существующими позициями,
    /// даже если они были созданы через другой UI и хранят symbol/exchange раздельно.
    var identityKey: String {
        let marketKey = Self.identityMarketKey(for: normalizedMarket)
        return "\(marketKey)|\(normalizedSymbol)"
    }

    var mergeKey: String {
        "\(normalizedMarket ?? "")|\(normalizedSymbol)"
    }

    static func identityMarketKey(for market: String?) -> String {
        switch market {
        case "US", "NASDAQ", "NYSE", "AMEX", "BATS", "IEX":
            return "US"
        case let market?:
            return market
        case nil:
            return ""
        }
    }

    static func canonicalTicker(from rawSymbol: String) -> String {
        let trimmed = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return "" }

        if trimmed.contains(":"),
           let last = trimmed.split(separator: ":", maxSplits: 1).last {
            return String(last)
        }

        if trimmed.contains("."),
           let first = trimmed.split(separator: ".", maxSplits: 1).first {
            return String(first)
        }

        return trimmed
    }

    private func uniqueQuoteSymbols(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }
    }
}

struct StockBulkImportParsedRow: Equatable, Sendable {
    let rawLine: String
    let ticker: String
    let market: String?
    let quantity: Double?
    let buyPrice: Double?
    let sourceOrderIndex: Int
}

enum StockBulkImportRowStatus: String, Sendable {
    case found
    case priceMissing
    case ambiguous
    case notFound

    var localizedLabel: String {
        switch self {
        case .found:
            return String(
                localized: "finances.mass_import.status.found",
                defaultValue: "Найдено",
                comment: "Mass import status when ticker and price are ready"
            )
        case .priceMissing:
            return String(
                localized: "finances.mass_import.status.price_missing",
                defaultValue: "Нет цены",
                comment: "Mass import status when ticker is found but current price is unavailable"
            )
        case .ambiguous:
            return String(
                localized: "finances.mass_import.status.ambiguous",
                defaultValue: "Уточнить",
                comment: "Mass import status when multiple instruments match"
            )
        case .notFound:
            return String(
                localized: "finances.mass_import.status.not_found",
                defaultValue: "Не найдено",
                comment: "Mass import status when no instrument match exists"
            )
        }
    }
}

struct StockBulkImportRowDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let rawLine: String
    var tickerText: String
    var marketText: String
    var quantityText: String
    var buyPriceText: String
    var currentPriceText: String
    let sourceOrderIndex: Int
    var candidates: [StockBulkImportCandidate]
    var selectedCandidate: StockBulkImportCandidate?

    init(
        id: UUID = UUID(),
        rawLine: String,
        tickerText: String,
        marketText: String,
        quantityText: String,
        buyPriceText: String,
        currentPriceText: String = "",
        sourceOrderIndex: Int,
        candidates: [StockBulkImportCandidate],
        selectedCandidate: StockBulkImportCandidate?
    ) {
        self.id = id
        self.rawLine = rawLine
        self.tickerText = tickerText
        self.marketText = marketText
        self.quantityText = quantityText
        self.buyPriceText = buyPriceText
        self.currentPriceText = currentPriceText
        self.sourceOrderIndex = sourceOrderIndex
        self.candidates = candidates
        self.selectedCandidate = selectedCandidate
    }

    var ticker: String {
        tickerText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var market: String? {
        let trimmed = marketText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }

    var quantity: Double? {
        StockBulkImportNumberParser.parse(quantityText)
    }

    var buyPrice: Double? {
        StockBulkImportNumberParser.parse(buyPriceText)
    }

    var currentPrice: Double? {
        StockBulkImportNumberParser.parse(currentPriceText)
    }

    var status: StockBulkImportRowStatus {
        if selectedCandidate != nil {
            return currentPrice != nil ? .found : .priceMissing
        }
        if candidates.isEmpty {
            return .notFound
        }
        return .ambiguous
    }

    var requiresAttention: Bool {
        status != .found
    }

    var isAddable: Bool {
        guard selectedCandidate != nil else { return false }
        guard let quantity, quantity > 0 else { return false }
        return buyPrice != nil
    }
}

extension StockBulkImportRowDraft {
    /// Символ для превью: в header оставляем только тикер без технического market-prefix.
    var displayHeaderSymbol: String {
        if let selectedCandidate {
            return selectedCandidate.normalizedSymbol
        }
        return ticker
    }

    /// Вторичная строка для превью: имя инструмента, либо сырой распознанный текст (когда нет матча).
    var displaySecondaryText: String? {
        if let selectedCandidate {
            return selectedCandidate.displayName
        }

        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Сырой текст полезен только до выбора инструмента (иначе это часто дублирует имя).
    var shouldShowRawLineAsSecondaryText: Bool {
        selectedCandidate == nil
    }
}

struct StockBulkImportResolvedRow: Equatable, Sendable {
    let candidate: StockBulkImportCandidate
    let quantity: Double
    let buyPrice: Double
    let currentPrice: Double?
    let sourceOrderIndex: Int
}

enum StockBulkImportMode: String, CaseIterable, Identifiable {
    case screenshot
    case manual

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .screenshot:
            return "finances.mass_import.mode.screenshot"
        case .manual:
            return "finances.mass_import.mode.manual"
        }
    }
}

enum StockBulkImportPriorityOption: Int, CaseIterable, Identifiable {
    case zero = 0
    case one = 1
    case two = 2

    var id: Int { rawValue }

    var investmentPriority: InvestmentPriority {
        switch self {
        case .zero:
            return .high
        case .one:
            return .normal
        case .two:
            return .low
        }
    }
}

enum StockBulkImportMarketNormalizer {
    private static let aliases: [String: String] = [
        "NASDAQ": "NASDAQ",
        "NAS": "NASDAQ",
        "NYSE": "NYSE",
        "NYQ": "NYSE",
        "AMEX": "AMEX",
        "ARCX": "AMEX",
        "ARCA": "AMEX",
        "BATS": "BATS",
        "IEX": "IEX",
        "MOEX": "MOEX",
        "MISX": "MOEX",
        "SPB": "SPBX",
        "SPBX": "SPBX",
        "LSE": "LSE",
        "LON": "LSE",
        "US": "US",
        "USR": "US"
    ]

    static func normalize(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !trimmed.isEmpty else { return nil }
        return aliases[trimmed]
    }
}
