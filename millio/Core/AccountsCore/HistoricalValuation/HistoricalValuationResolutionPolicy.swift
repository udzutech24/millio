import Foundation

/// Deterministic ISO 4217 allow-list for persisted account and display currencies.
///
/// `Locale.commonISOCurrencyCodes` is intentionally not used here: its contents vary with the
/// platform data set, which would make the same historical input publishable on one OS and
/// unavailable on another. The list is versioned with the valuation policy; additions therefore
/// require an explicit code review instead of accepting any syntactically valid `AAA` token.
enum HistoricalValuationCurrencyCode {
    static let supported: Set<String> = [
        "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
        "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BOV",
        "BRL", "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHE", "CHF",
        "CHW", "CLF", "CLP", "CNY", "COP", "COU", "CRC", "CUP", "CVE", "CZK",
        "DJF", "DKK", "DOP", "DZD", "EGP", "ERN", "ETB", "EUR", "FJD", "FKP",
        "GBP", "GEL", "GHS", "GIP", "GMD", "GNF", "GTQ", "GYD", "HKD", "HNL",
        "HTG", "HUF", "IDR", "ILS", "INR", "IQD", "IRR", "ISK", "JMD", "JOD",
        "JPY", "KES", "KGS", "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT",
        "LAK", "LBP", "LKR", "LRD", "LSL", "LYD", "MAD", "MDL", "MGA", "MKD",
        "MMK", "MNT", "MOP", "MRU", "MUR", "MVR", "MWK", "MXN", "MXV", "MYR",
        "MZN", "NAD", "NGN", "NIO", "NOK", "NPR", "NZD", "OMR", "PAB", "PEN",
        "PGK", "PHP", "PKR", "PLN", "PYG", "QAR", "RON", "RSD", "RUB", "RWF",
        "SAR", "SBD", "SCR", "SDG", "SEK", "SGD", "SHP", "SLE", "SOS", "SRD",
        "SSP", "STN", "SVC", "SYP", "SZL", "THB", "TJS", "TMT", "TND", "TOP",
        "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD", "USN", "UYI", "UYU",
        "UYW", "UZS", "VED", "VES", "VND", "VUV", "WST", "XAF", "XAG", "XAU",
        "XBA", "XBB", "XBC", "XBD", "XCD", "XDR", "XOF", "XPD", "XPF", "XPT",
        "XSU", "XTS", "XUA", "YER", "ZAR", "ZMW", "ZWG"
    ]

    static func normalized(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isSupported(_ rawValue: String) -> Bool {
        supported.contains(normalized(rawValue))
    }
}

enum HistoricalValuationWeekday: Int, Codable, CaseIterable, Hashable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
}

/// Versioned provider/exchange schedule used to prove that an older record is the applicable
/// previous close. An arbitrary older cache row is never sufficient evidence on its own.
struct HistoricalValuationCalendarPolicy: Codable, Hashable, Sendable {
    enum MarketKind: String, Codable, Hashable, Sendable {
        case fiat
        case exchange
        case continuous24x7
    }

    let id: String
    let marketKind: MarketKind
    let openWeekdays: Set<HistoricalValuationWeekday>
    let holidays: Set<String>
    let maximumLookbackDays: Int

    static func fiat(
        id: String,
        holidays: Set<String> = [],
        maximumLookbackDays: Int = 14
    ) -> Self {
        Self(
            id: id,
            marketKind: .fiat,
            openWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            holidays: holidays,
            maximumLookbackDays: maximumLookbackDays
        )
    }

    static func exchange(
        id: String,
        openWeekdays: Set<HistoricalValuationWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        holidays: Set<String> = [],
        maximumLookbackDays: Int = 14
    ) -> Self {
        Self(
            id: id,
            marketKind: .exchange,
            openWeekdays: openWeekdays,
            holidays: holidays,
            maximumLookbackDays: maximumLookbackDays
        )
    }

    static func crypto24x7(id: String) -> Self {
        Self(
            id: id,
            marketKind: .continuous24x7,
            openWeekdays: Set(HistoricalValuationWeekday.allCases),
            holidays: [],
            maximumLookbackDays: 1
        )
    }

    /// Previous close is legal only when the candidate was an open day and every following day
    /// through the requested date is explicitly closed by this policy. Therefore an ordinary
    /// weekday miss, a skipped trading day and a 24x7 miss cannot silently forward-fill.
    func allowsPreviousClose(from candidateDayKey: String, for requestedDayKey: String) -> Bool {
        guard maximumLookbackDays > 0,
              let candidate = Self.date(from: candidateDayKey),
              let requested = Self.date(from: requestedDayKey),
              candidate < requested,
              isOpen(candidateDayKey),
              !isOpen(requestedDayKey) else {
            return false
        }

        let calendar = Self.calendar
        guard let dayDistance = calendar.dateComponents([.day], from: candidate, to: requested).day,
              (1...maximumLookbackDays).contains(dayDistance) else {
            return false
        }

        var cursor = candidate
        for _ in 1...dayDistance {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return false }
            cursor = next
            if cursor < requested, isOpen(Self.dayKey(for: cursor)) {
                return false
            }
        }
        return true
    }

    private func isOpen(_ dayKey: String) -> Bool {
        guard marketKind != .continuous24x7 || !openWeekdays.isEmpty,
              let date = Self.date(from: dayKey),
              !holidays.contains(dayKey),
              let weekday = HistoricalValuationWeekday(rawValue: Self.calendar.component(.weekday, from: date)) else {
            return false
        }
        return openWeekdays.contains(weekday)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func date(from dayKey: String) -> Date? {
        let components = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self.dayKey(for: date) == dayKey else {
            return nil
        }
        return date
    }

    private static func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

enum HistoricalValuationResolutionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case nativeParity
    case exact
    case previousClose
    case frozenClose
    case currentEstimate
    case unavailable
}

struct HistoricalValuationResolutionProvenance: Codable, Hashable, Sendable {
    let sourceID: String
    let recordID: String
    let evidenceDayKey: String
    let observedAt: Date
    let calendarPolicyID: String
}

struct HistoricalValuationEvidenceRecord: Codable, Hashable, Sendable {
    let value: Decimal
    let dayKey: String
    let recordID: String
    let sourceID: String
    let observedAt: Date
}

/// Provider output is deliberately split by evidence semantics. A row returned in
/// `previousClose` is still re-validated against the explicit calendar policy by the resolver.
struct HistoricalValuationEvidenceBundle: Codable, Hashable, Sendable {
    let exact: [HistoricalValuationEvidenceRecord]
    let previousClose: [HistoricalValuationEvidenceRecord]
    let frozenClose: [HistoricalValuationEvidenceRecord]
    let currentEstimate: [HistoricalValuationEvidenceRecord]

    init(
        exact: [HistoricalValuationEvidenceRecord] = [],
        previousClose: [HistoricalValuationEvidenceRecord] = [],
        frozenClose: [HistoricalValuationEvidenceRecord] = [],
        currentEstimate: [HistoricalValuationEvidenceRecord] = []
    ) {
        self.exact = exact
        self.previousClose = previousClose
        self.frozenClose = frozenClose
        self.currentEstimate = currentEstimate
    }
}

struct HistoricalFXPair: Codable, Hashable, Sendable {
    let base: String
    let quote: String

    init(base: String, quote: String) {
        self.base = base.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.quote = quote.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct HistoricalFXDependencyKey: Codable, Hashable, Sendable {
    let dayKey: String
    let pair: HistoricalFXPair
}

struct HistoricalMarketInstrument: Codable, Hashable, Sendable {
    let symbol: String
    let assetClass: MarketAssetClass

    init(symbol: String, assetClass: MarketAssetClass) {
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.assetClass = assetClass
    }
}

struct HistoricalMarketDependencyKey: Codable, Hashable, Sendable {
    let dayKey: String
    let instrument: HistoricalMarketInstrument
}

protocol HistoricalValuationEvidenceProviding: Sendable {
    /// Implementations receive every unique day/pair in one call and may perform I/O off the
    /// MainActor. They must not issue a network request for each account contribution.
    func fetchFXEvidence(
        for dependencies: Set<HistoricalFXDependencyKey>
    ) async throws -> [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle]

    /// Implementations receive every unique day/instrument in one call.
    func fetchMarketEvidence(
        for dependencies: Set<HistoricalMarketDependencyKey>
    ) async throws -> [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle]
}
