//
//  CashflowBulkExpenseImportParser.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

import Foundation
import UIKit
@preconcurrency import Vision

protocol CashflowBulkExpenseImportTextRecognizing {
    func recognizeLines(in image: CGImage) async throws -> [String]
}

struct VisionCashflowBulkExpenseImportTextRecognizer: CashflowBulkExpenseImportTextRecognizing {
    func recognizeLines(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let orderedLines = observations
                    .compactMap { observation -> (String, CGRect)? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return (candidate.string, observation.boundingBox)
                    }
                    .sorted { lhs, rhs in
                        let diff = abs(lhs.1.midY - rhs.1.midY)
                        if diff > 0.02 {
                            return lhs.1.midY > rhs.1.midY
                        }
                        return lhs.1.minX < rhs.1.minX
                    }
                    .map(\.0)

                continuation.resume(returning: orderedLines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ru-RU", "en-US"]

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

struct CashflowBulkExpenseImportParser {
    private let textRecognizer: any CashflowBulkExpenseImportTextRecognizing

    init(
        textRecognizer: any CashflowBulkExpenseImportTextRecognizing = VisionCashflowBulkExpenseImportTextRecognizer()
    ) {
        self.textRecognizer = textRecognizer
    }

    func parseScreenshots(from imageDataList: [Data]) async throws -> [CashflowBulkExpenseParsedRow] {
        guard !imageDataList.isEmpty else {
            throw CashflowBulkExpenseImportError.noTextFound
        }

        var recognizedLines: [String] = []
        for imageData in imageDataList.prefix(8) {
            guard let image = UIImage(data: imageData)?.cgImage else {
                throw CashflowBulkExpenseImportError.invalidImage
            }
            recognizedLines.append(contentsOf: try await textRecognizer.recognizeLines(in: image))
        }

        guard !recognizedLines.isEmpty else {
            throw CashflowBulkExpenseImportError.noTextFound
        }

        let rows = Self.parseRecognizedLines(recognizedLines)
        guard !rows.isEmpty else {
            throw CashflowBulkExpenseImportError.noExpenseRowsFound
        }
        return rows
    }

    static func parseManualInput(_ text: String) -> [CashflowBulkExpenseParsedRow] {
        parseRecognizedLines(text.components(separatedBy: .newlines))
    }

    static func parseRecognizedLines(_ lines: [String]) -> [CashflowBulkExpenseParsedRow] {
        let normalizedLines = lines
            .map(normalizeLine)
            .filter { !$0.isEmpty }

        var rows: [CashflowBulkExpenseParsedRow] = []
        var index = 0

        while index < normalizedLines.count {
            let line = normalizedLines[index]

            if shouldSkipLine(line) {
                index += 1
                continue
            }

            if let parsed = parseInlineExpenseLine(line, sourceOrderIndex: rows.count) {
                rows.append(parsed)
                index += 1
                continue
            }

            if isLikelyTitleLine(line) {
                let nextLine = normalizedLines[safe: index + 1]
                let thirdLine = normalizedLines[safe: index + 2]

                if let nextLine,
                   let amount = parseAmount(from: nextLine),
                   let title = normalizeTitle(line),
                   !shouldRejectPair(title: title, amountLine: nextLine) {
                    rows.append(
                        CashflowBulkExpenseParsedRow(
                            rawLine: "\(line) \(nextLine)",
                            title: title,
                            amount: amount,
                            sourceOrderIndex: rows.count
                        )
                    )
                    index += 2
                    continue
                }

                if let nextLine,
                   isLikelyTitleLine(nextLine),
                   let thirdLine,
                   let amount = parseAmount(from: thirdLine) {
                    let combinedTitle = [normalizeTitle(line), normalizeTitle(nextLine)]
                        .compactMap { $0 }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !combinedTitle.isEmpty, !shouldRejectPair(title: combinedTitle, amountLine: thirdLine) {
                        rows.append(
                            CashflowBulkExpenseParsedRow(
                                rawLine: "\(line) \(nextLine) \(thirdLine)",
                                title: combinedTitle,
                                amount: amount,
                                sourceOrderIndex: rows.count
                            )
                        )
                        index += 3
                        continue
                    }
                }
            }

            index += 1
        }

        return rows
    }

    private static func parseInlineExpenseLine(_ line: String, sourceOrderIndex: Int) -> CashflowBulkExpenseParsedRow? {
        let pattern = #"^(.*?)([-−]?\d[\d\s.,]{0,16})\s*(?:₽|руб\.?|RUB|р|€|\$|USD|EUR)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 3,
              let titleRange = Range(match.range(at: 1), in: line),
              let amountRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let amountText = String(line[amountRange])
        guard let amount = parseAmount(from: amountText) else { return nil }
        guard let title = normalizeTitle(String(line[titleRange])), !shouldRejectPair(title: title, amountLine: amountText) else {
            return nil
        }

        return CashflowBulkExpenseParsedRow(
            rawLine: line,
            title: title,
            amount: amount,
            sourceOrderIndex: sourceOrderIndex
        )
    }

    private static func parseAmount(from line: String) -> Double? {
        guard !line.contains("+") else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        return CashflowBulkExpenseRowDraft.parseAmount(trimmed)
    }

    private static func shouldRejectPair(title: String, amountLine: String) -> Bool {
        let normalizedTitle = normalizeSearchableText(title)
        let lowercasedAmount = amountLine.lowercased()
        if normalizedTitle.isEmpty { return true }
        if ignoredTitleKeywords.contains(where: normalizedTitle.contains) { return true }
        if incomeKeywords.contains(where: normalizedTitle.contains) { return true }
        if lowercasedAmount.contains("+") { return true }
        if normalizedTitle.allSatisfy({ $0.isNumber || $0 == " " || $0 == ":" || $0 == "." }) { return true }
        return false
    }

    private static func shouldSkipLine(_ line: String) -> Bool {
        let normalized = normalizeSearchableText(line)
        guard !normalized.isEmpty else { return true }
        if ignoredTitleKeywords.contains(where: normalized.contains) {
            return true
        }
        if incomeKeywords.contains(where: normalized.contains) && !normalized.contains("оплата") {
            return true
        }
        if normalized.range(of: #"^\d{1,2}[:.]\d{2}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isLikelyTitleLine(_ line: String) -> Bool {
        guard normalizeTitle(line) != nil else { return false }
        return parseAmount(from: line) == nil
    }

    private static func normalizeTitle(_ raw: String) -> String? {
        var value = raw
            .replacingOccurrences(of: #"\b\d{1,2}[./]\d{1,2}(?:[./]\d{2,4})?\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d{1,2}:\d{2}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[*•·]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[↗→]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-–—:;,."))
        guard !value.isEmpty else { return nil }
        let searchable = normalizeSearchableText(value)
        guard searchable.contains(where: { $0.isLetter }) else { return nil }
        return value
    }

    private static func normalizeLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "₽", with: " ₽")
            .replacingOccurrences(of: #"(?<=\d),(?=\d{3}\b)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeSearchableText(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let ignoredTitleKeywords: [String] = [
        "история",
        "операции",
        "списания",
        "выписка",
        "баланс",
        "доступно",
        "остаток",
        "карта",
        "счет",
        "счёт",
        "total",
        "available",
        "statement",
        "posted",
        "pending",
        "today",
        "yesterday"
    ]

    private static let incomeKeywords: [String] = [
        "пополнение",
        "зачисление",
        "возврат",
        "cashback",
        "кешбэк",
        "income",
        "refund",
        "top up"
    ]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
