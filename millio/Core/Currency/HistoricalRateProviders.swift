//
//  HistoricalRateProviders.swift
//  millio
//
//  Created by Codex on 20.03.2026.
//

import Foundation

protocol HistoricalRateProvider {
    func fetchRate(on date: Date, from: String, to: String, loader: HTTPDataLoading) async -> Double?
    func resetTransientCache()
}

final class FrankfurterHistoricalRateProvider: HistoricalRateProvider {
    private static let supportedCurrencies: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD",
        "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK",
        "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"
    ]

    private var knownUnsupportedPairs: Set<String> = []
    private var knownUnavailableRequests: Set<String> = []
    private var failureLogDedup: Set<String> = []

    func fetchRate(on date: Date, from: String, to: String, loader: HTTPDataLoading) async -> Double? {
        let dateString = Self.formatDateForFrankfurter(date)
        let pairKey = "\(from)->\(to)"
        let requestKey = "\(dateString)|\(pairKey)"

        guard Self.supportedCurrencies.contains(from),
              Self.supportedCurrencies.contains(to) else {
            knownUnsupportedPairs.insert(pairKey)
            knownUnavailableRequests.insert(requestKey)
            return nil
        }

        if knownUnsupportedPairs.contains(pairKey) {
            return nil
        }
        if knownUnavailableRequests.contains(requestKey) {
            return nil
        }

        guard let url = URL(string: "https://api.frankfurter.app/\(dateString)?from=\(from)&to=\(to)") else {
            return nil
        }

        do {
            let (data, response) = try await loader.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200..<300).contains(http.statusCode) else {
                let statusCode = http.statusCode
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let bodySnippet = body?.prefix(180) ?? ""
                let logKey = "\(requestKey)|\(statusCode)"

                if failureLogDedup.insert(logKey).inserted {
                    AppLogger.log(
                        .warning,
                        category: "CurrencyRateService",
                        "Historical rate API HTTP \(statusCode) for \(pairKey) on \(dateString). \(bodySnippet)"
                    )
                }

                if statusCode == 400 {
                    knownUnsupportedPairs.insert(pairKey)
                    knownUnavailableRequests.insert(requestKey)
                    return nil
                }
                if statusCode == 404 || statusCode == 429 {
                    knownUnavailableRequests.insert(requestKey)
                    return nil
                }

                throw URLError(.badServerResponse)
            }

            struct FrankfurterResponse: Decodable {
                let rates: [String: Double]
            }

            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            guard let rate = decoded.rates[to] else {
                knownUnavailableRequests.insert(requestKey)
                return nil
            }
            return rate
        } catch {
            let nsError = error as NSError
            let logKey = "\(requestKey)|\(nsError.domain)|\(nsError.code)"
            if failureLogDedup.insert(logKey).inserted {
                AppLogger.log(
                    .error,
                    category: "CurrencyRateService",
                    "Failed to fetch historical rate for \(pairKey) on \(dateString): \(error.localizedDescription)"
                )
            }
            return nil
        }
    }

    func resetTransientCache() {
        knownUnavailableRequests.removeAll()
        failureLogDedup.removeAll()
    }

    private static func formatDateForFrankfurter(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

final class CBRHistoricalRateProvider: HistoricalRateProvider {
    private var knownUnavailableRequests: Set<String> = []
    private var failureLogDedup: Set<String> = []
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func fetchRate(on date: Date, from: String, to: String, loader: HTTPDataLoading) async -> Double? {
        let base = from.uppercased()
        let quote = to.uppercased()
        guard base == "RUB" || quote == "RUB" else { return nil }

        let targetDate = calendar.startOfDay(for: date)
        let requestKey = requestCacheKey(on: targetDate, from: base, to: quote)
        if knownUnavailableRequests.contains(requestKey) {
            return nil
        }

        guard let url = makeDailyURL(for: targetDate) else {
            return nil
        }

        do {
            let (data, response) = try await loader.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                knownUnavailableRequests.insert(requestKey)
                AppLogger.log(
                    .warning,
                    category: "CurrencyRateService",
                    "CBR historical API HTTP \(http.statusCode) for \(base)->\(quote) on \(formatCBRRequestDate(targetDate))"
                )
                return nil
            }

            let parser = CBRDailyRatesParser()
            let payload = try parser.parse(data: data)

            // CBR может вернуть соседнюю рабочую дату. Для exact-истории в кеш
            // принимаем только точное совпадение дня.
            let parsedDay = calendar.startOfDay(for: payload.date)
            guard parsedDay == targetDate else {
                knownUnavailableRequests.insert(requestKey)
                return nil
            }

            var rubPerCurrency = payload.rubPerCurrency
            rubPerCurrency["RUB"] = 1.0

            guard let rubPerBase = rubPerCurrency[base],
                  let rubPerQuote = rubPerCurrency[quote],
                  rubPerBase > 0,
                  rubPerQuote > 0 else {
                knownUnavailableRequests.insert(requestKey)
                return nil
            }

            return rubPerBase / rubPerQuote
        } catch {
            let nsError = error as NSError
            let logKey = "\(requestKey)|\(nsError.domain)|\(nsError.code)"
            if failureLogDedup.insert(logKey).inserted {
                AppLogger.log(
                    .error,
                    category: "CurrencyRateService",
                    "Failed to fetch CBR historical rate for \(base)->\(quote): \(error.localizedDescription)"
                )
            }
            return nil
        }
    }

    func resetTransientCache() {
        knownUnavailableRequests.removeAll()
        failureLogDedup.removeAll()
    }

    private func requestCacheKey(on date: Date, from: String, to: String) -> String {
        let ts = Int(date.timeIntervalSince1970)
        return "\(ts)|\(from)->\(to)"
    }

    private func makeDailyURL(for date: Date) -> URL? {
        var components = URLComponents(string: "https://www.cbr.ru/scripts/XML_daily.asp")
        components?.queryItems = [
            URLQueryItem(name: "date_req", value: formatCBRRequestDate(date))
        ]
        return components?.url
    }

    private func formatCBRRequestDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}

private struct CBRDailyRatesPayload {
    let date: Date
    let rubPerCurrency: [String: Double]
}

private final class CBRDailyRatesParser: NSObject, XMLParserDelegate {
    private var parsedDate: Date?
    private var currentElement: String = ""
    private var currentCharCode: String = ""
    private var currentNominal: String = ""
    private var currentValue: String = ""
    private var rates: [String: Double] = [:]

    func parse(data: Data) throws -> CBRDailyRatesPayload {
        parsedDate = nil
        currentElement = ""
        currentCharCode = ""
        currentNominal = ""
        currentValue = ""
        rates = [:]

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }

        guard let date = parsedDate else {
            throw URLError(.cannotParseResponse)
        }

        return CBRDailyRatesPayload(date: date, rubPerCurrency: rates)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "ValCurs", let dateString = attributeDict["Date"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.timeZone = Calendar.current.timeZone
            formatter.dateFormat = "dd.MM.yyyy"
            parsedDate = formatter.date(from: dateString)
        } else if elementName == "Valute" {
            currentCharCode = ""
            currentNominal = ""
            currentValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "CharCode":
            currentCharCode += string
        case "Nominal":
            currentNominal += string
        case "Value":
            currentValue += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Valute" {
            let code = currentCharCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let nominalString = currentNominal
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            let valueString = currentValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")

            if let nominal = Double(nominalString),
               let value = Double(valueString),
               nominal > 0,
               value > 0,
               !code.isEmpty {
                rates[code] = value / nominal
            }
        }
        currentElement = ""
    }
}
