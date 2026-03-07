import Foundation
import UIKit
@preconcurrency import Vision

enum StockBulkImportParserError: LocalizedError {
    case invalidImage
    case noTextFound
    case noTickerRowsFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return FinancesL10n.tr("finances.mass_import.error.invalid_image")
        case .noTextFound:
            return FinancesL10n.tr("finances.mass_import.error.no_text")
        case .noTickerRowsFound:
            return FinancesL10n.tr("finances.mass_import.error.no_rows")
        }
    }
}

protocol StockBulkImportTextRecognizing {
    func recognizeLines(in image: CGImage) async throws -> [String]
}

struct VisionStockBulkImportTextRecognizer: StockBulkImportTextRecognizing {
    func recognizeLines(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .compactMap { observation -> (String, CGRect)? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return (candidate.string, observation.boundingBox)
                    }
                    .sorted { lhs, rhs in
                        let yDelta = abs(lhs.1.midY - rhs.1.midY)
                        if yDelta > 0.02 {
                            return lhs.1.midY > rhs.1.midY
                        }
                        return lhs.1.minX < rhs.1.minX
                    }
                    .map(\.0)

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "ru-RU", "es-ES", "zh-Hans", "ar"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct StockBulkImportParser {
    private let textRecognizer: any StockBulkImportTextRecognizing

    init(textRecognizer: any StockBulkImportTextRecognizing = VisionStockBulkImportTextRecognizer()) {
        self.textRecognizer = textRecognizer
    }

    func parseScreenshots(from imageDataList: [Data]) async throws -> [StockBulkImportParsedRow] {
        guard !imageDataList.isEmpty else {
            throw StockBulkImportParserError.noTextFound
        }

        var recognizedLines: [String] = []
        for imageData in imageDataList.prefix(8) {
            guard let cgImage = UIImage(data: imageData)?.cgImage else {
                throw StockBulkImportParserError.invalidImage
            }
            recognizedLines.append(contentsOf: try await textRecognizer.recognizeLines(in: cgImage))
        }

        guard !recognizedLines.isEmpty else {
            throw StockBulkImportParserError.noTextFound
        }

        let parsedRows = Self.parseRecognizedLines(recognizedLines)
        guard !parsedRows.isEmpty else {
            throw StockBulkImportParserError.noTickerRowsFound
        }

        return parsedRows
    }

    static func parseRecognizedLines(_ lines: [String]) -> [StockBulkImportParsedRow] {
        let normalizedLines = lines.map(normalizeLine)
        var parsedRows: [StockBulkImportParsedRow] = []
        var seenKeys: Set<String> = []

        for (lineIndex, line) in normalizedLines.enumerated() {
            guard !line.isEmpty else { continue }
            guard isLikelyTickerCarrierLine(line) else { continue }

            let explicitMatches = extractExplicitTickerMatches(from: line)
            if !explicitMatches.isEmpty {
                for match in explicitMatches {
                    let row = makeParsedRow(
                        rawLine: lines[lineIndex],
                        ticker: match.ticker,
                        market: match.market,
                        sourceIndex: lineIndex,
                        normalizedLines: normalizedLines
                    )
                    let key = "\(lineIndex)|\(row.market ?? "")|\(row.ticker)"
                    if seenKeys.insert(key).inserted {
                        parsedRows.append(row)
                    }
                }
                continue
            }

            for token in extractStandaloneTickers(from: line) {
                let row = makeParsedRow(
                    rawLine: lines[lineIndex],
                    ticker: token,
                    market: nil,
                    sourceIndex: lineIndex,
                    normalizedLines: normalizedLines
                )
                let key = "\(lineIndex)||\(row.ticker)"
                if seenKeys.insert(key).inserted {
                    parsedRows.append(row)
                }
            }
        }

        return parsedRows.sorted { lhs, rhs in
            lhs.sourceOrderIndex < rhs.sourceOrderIndex
        }
    }

    static func extractQuantityAndPrice(around index: Int, in normalizedLines: [String]) -> (Double?, Double?) {
        let prioritizedIndexes = uniqueIndexes([
            index,
            index + 1,
            index + 2,
            index - 1,
            index - 2
        ], validRange: normalizedLines.indices)
        var quantity: Double?
        var price: Double?

        for candidateIndex in prioritizedIndexes {
            guard normalizedLines.indices.contains(candidateIndex) else { continue }
            let line = normalizedLines[candidateIndex]
            guard isLikelyPositionLine(line) || candidateIndex == index else { continue }

            let (inlineQuantity, inlinePrice) = parseInlineQuantityAndPrice(from: line)
            if inlineQuantity != nil || inlinePrice != nil {
                quantity = quantity ?? inlineQuantity
                price = price ?? inlinePrice
            }

            quantity = quantity ?? parseQuantity(from: line)
            price = price ?? parsePrice(from: line)

            if quantity != nil, price != nil {
                break
            }
        }

        return (quantity, price)
    }

    private static func makeParsedRow(
        rawLine: String,
        ticker: String,
        market: String?,
        sourceIndex: Int,
        normalizedLines: [String]
    ) -> StockBulkImportParsedRow {
        let (quantity, price) = extractQuantityAndPrice(around: sourceIndex, in: normalizedLines)
        return StockBulkImportParsedRow(
            rawLine: rawLine,
            ticker: ticker,
            market: StockBulkImportMarketNormalizer.normalize(market),
            quantity: quantity,
            buyPrice: price,
            sourceOrderIndex: sourceIndex
        )
    }

    private static func extractExplicitTickerMatches(from line: String) -> [(ticker: String, market: String?)] {
        let nsLine = line as NSString
        var matches: [(String, String?)] = []

        let marketPatterns = [
            #"\b([A-Z]{2,10})\s*[:\-]\s*([A-Z0-9]{1,8})\b"#,
            #"\b([A-Z0-9]{1,8})\.([A-Z]{2,10})\b"#
        ]

        for (index, pattern) in marketPatterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let results = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

            for result in results where result.numberOfRanges >= 3 {
                if index == 0 {
                    let market = nsLine.substring(with: result.range(at: 1))
                    let ticker = nsLine.substring(with: result.range(at: 2))
                    let normalizedTicker = sanitizeTicker(ticker)
                    if isValidTickerToken(normalizedTicker) {
                        matches.append((normalizedTicker, market))
                    }
                } else {
                    let ticker = nsLine.substring(with: result.range(at: 1))
                    let marketSuffix = nsLine.substring(with: result.range(at: 2))
                    let normalizedTicker = sanitizeTicker(ticker)
                    if isValidTickerToken(normalizedTicker) {
                        matches.append((normalizedTicker, marketSuffix))
                    }
                }
            }
        }

        return matches
    }

    private static func extractStandaloneTickers(from line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z0-9]{1,8}\b"#) else {
            return []
        }

        let nsLine = line as NSString
        let results = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        return results
            .map { nsLine.substring(with: $0.range) }
            .map(sanitizeTicker)
            .filter(isValidTickerToken)
    }

    private static func parseInlineQuantityAndPrice(from line: String) -> (Double?, Double?) {
        let patterns = [
            #"\b(\d+(?:[.,]\d+)?)\s*(?:ШТ\.?|WT\.?|WТ\.?|PCS|SHARES?)\W{0,6}(?:ПО|ПO|AT|@)\W{0,6}(\d+(?:[.,]\d+)?)\b"#,
            #"\b(\d+(?:[.,]\d+)?)\s*(?:ПО|AT|@)\s*(\d+(?:[.,]\d+)?)\b"#,
            #"\bQTY\s*[:=]?\s*(\d+(?:[.,]\d+)?)\b.*?(?:\bPRICE\b|AT|@|ПО)\s*[:=]?\s*(\d+(?:[.,]\d+)?)\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let quantityRange = Range(match.range(at: 1), in: line),
                  let priceRange = Range(match.range(at: 2), in: line) else {
                continue
            }

            let quantity = parseNumber(String(line[quantityRange]))
            let price = parseNumber(String(line[priceRange]))
            return (quantity, price)
        }

        return (nil, nil)
    }

    private static func parseQuantity(from line: String) -> Double? {
        let patterns = [
            #"\b(?:QTY|QUANTITY|КОЛ-?ВО)\s*[:=]?\s*(\d+(?:[.,]\d+)?)\b"#,
            #"\b(\d+(?:[.,]\d+)?)\s*(?:ШТ\.?|WT\.?|WТ\.?|PCS|SHARES?)\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let valueRange = Range(match.range(at: 1), in: line),
                  let value = parseNumber(String(line[valueRange])) else {
                continue
            }
            return value
        }

        return nil
    }

    private static func parsePrice(from line: String) -> Double? {
        let patterns = [
            #"(?:\bPRICE\b|\bBUY\b|\bCOST\b|@|AT|ПО|ЦЕНА)\s*[:=]?\s*(\d+(?:[.,]\d+)?)\b"#,
            #"\b(\d+(?:[.,]\d+)?)\s*(?:USD|US\$)\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let valueRange = Range(match.range(at: 1), in: line),
                  let value = parseNumber(String(line[valueRange])) else {
                continue
            }
            return value
        }

        return nil
    }

    private static func parseNumber(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static func sanitizeTicker(_ value: String) -> String {
        String(
            value
                .uppercased()
                .filter { $0.isLetter || $0.isNumber }
                .prefix(8)
        )
    }

    private static func isValidTickerToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        guard token.rangeOfCharacter(from: .letters) != nil else { return false }
        guard noiseWords.contains(token) == false else { return false }
        guard StockBulkImportMarketNormalizer.normalize(token) == nil else { return false }
        return true
    }

    private static func isLikelyTickerCarrierLine(_ line: String) -> Bool {
        guard !line.contains("#") else { return false }
        guard line.contains("ПОРТФЕЛ") == false else { return false }
        guard line.contains("ПРИКАЗ") == false else { return false }
        guard line.contains("СДЕЛК") == false else { return false }
        guard line.contains("АКЦИИ") == false else { return false }
        guard line.contains("TRADERNET") == false else { return false }
        guard line.contains("КОТИРОВКИ") == false else { return false }
        guard line.contains("МЕНЮ") == false else { return false }
        return true
    }

    private static func isLikelyPositionLine(_ line: String) -> Bool {
        line.contains("ШТ") ||
        line.contains("WT") ||
        line.contains("WТ") ||
        line.contains("PCS") ||
        line.contains("SHARE") ||
        line.contains("QTY") ||
        line.contains("КОЛ-") ||
        line.contains(" ПО ") ||
        line.contains("@") ||
        line.contains(" AT ")
    }

    private static func uniqueIndexes(_ values: [Int], validRange: Range<Int>) -> [Int] {
        var result: [Int] = []
        for value in values where validRange.contains(value) {
            if result.contains(value) == false {
                result.append(value)
            }
        }
        return result
    }

    private static func normalizeLine(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "＠", with: "@")
            .replacingOccurrences(of: "ПO", with: "ПО")
            .replacingOccurrences(of: "РO", with: "РО")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let noiseWords: Set<String> = [
        "USD", "RUB", "EUR", "TOTAL", "PRICE", "OPEN", "CLOSE", "BUY", "SELL", "LIMIT",
        "VALUE", "PORTFOLIO", "POSITIONS", "POSITION", "BALANCE", "TODAY", "SHARES", "QTY",
        "ACCOUNT", "WATCH", "WATCHLIST", "DAY", "GAIN", "LOSS", "COST", "AVG", "AVERAGE"
    ]
}
