//
//  CashbackScreenshotParser.swift
//  millio
//
//  Created by Codex on 26.02.2026.
//

import Foundation
import UIKit
@preconcurrency import Vision

/// Одна распознанная категория кешбэка из скриншота банка.
struct CashbackScreenshotImportItem: Equatable {
    let categoryName: String
    let percentage: Double
}

enum CashbackScreenshotImportError: LocalizedError {
    case invalidImage
    case noTextFound
    case noCashbackLinesFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Не удалось открыть изображение. Выберите другой скриншот."
        case .noTextFound:
            return "Текст на скриншоте не распознан."
        case .noCashbackLinesFound:
            return "Не нашёл строки с кешбэком формата «5% Категория» или «Категория +5%»."
        }
    }
}

protocol CashbackScreenshotTextRecognizing {
    func recognizeLines(in image: CGImage) async throws -> [String]
}

struct VisionCashbackScreenshotTextRecognizer: CashbackScreenshotTextRecognizing {
    func recognizeLines(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                guard !observations.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }

                let orderedLines = observations
                    .compactMap { observation -> (text: String, rect: CGRect)? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return (candidate.string, observation.boundingBox)
                    }
                    .sorted { lhs, rhs in
                        let yDiff = abs(lhs.rect.midY - rhs.rect.midY)
                        if yDiff > 0.02 {
                            return lhs.rect.midY > rhs.rect.midY
                        }
                        return lhs.rect.minX < rhs.rect.minX
                    }
                    .map(\.text)

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

/// Парсер скриншотов с категориями кешбэка. Распознаёт строки вида
/// `5% Супермаркеты`, `до 10% Отели` и `Супермаркеты +5%`.
struct CashbackScreenshotParser {
    private let textRecognizer: any CashbackScreenshotTextRecognizing

    init(textRecognizer: any CashbackScreenshotTextRecognizing = VisionCashbackScreenshotTextRecognizer()) {
        self.textRecognizer = textRecognizer
    }

    func parse(from imageData: Data) async throws -> [CashbackScreenshotImportItem] {
        guard let image = UIImage(data: imageData)?.cgImage else {
            throw CashbackScreenshotImportError.invalidImage
        }

        let lines = try await textRecognizer.recognizeLines(in: image)
        guard !lines.isEmpty else {
            throw CashbackScreenshotImportError.noTextFound
        }

        let parsed = Self.parseRecognizedLines(lines)
        guard !parsed.isEmpty else {
            throw CashbackScreenshotImportError.noCashbackLinesFound
        }

        return parsed
    }

    static func parseRecognizedLines(_ lines: [String]) -> [CashbackScreenshotImportItem] {
        var parsedItems: [CashbackScreenshotImportItem] = []
        var index = 0

        while index < lines.count {
            let currentLine = normalizeLine(lines[index])
            guard !currentLine.isEmpty else {
                index += 1
                continue
            }

            if let (percentage, categoryName) = parseInlineCashbackLine(currentLine) {
                parsedItems.append(
                    CashbackScreenshotImportItem(
                        categoryName: categoryName,
                        percentage: percentage
                    )
                )
                index += 1
                continue
            }

            if let (percentage, categoryName) = parseTrailingCashbackLine(currentLine) {
                parsedItems.append(
                    CashbackScreenshotImportItem(
                        categoryName: categoryName,
                        percentage: percentage
                    )
                )
                index += 1
                continue
            }

            if let percentage = parsePercentageOnlyLine(currentLine),
               index + 1 < lines.count {
                let categoryCandidate = normalizeCategoryName(lines[index + 1])
                if !categoryCandidate.isEmpty, categoryCandidate.contains("%") == false {
                    parsedItems.append(
                        CashbackScreenshotImportItem(
                            categoryName: categoryCandidate,
                            percentage: percentage
                        )
                    )
                    index += 2
                    continue
                }
            }

            index += 1
        }

        return deduplicateKeepingMaxPercentage(parsedItems)
    }

    private static func parseInlineCashbackLine(_ line: String) -> (Double, String)? {
        let pattern = #"^(?:[^\d]{0,8}\s*)?(?:до\s*)?(\d{1,3}(?:[.,]\d{1,2})?)\s*(?:%|％|°/o|°/о|o/o|о/о)\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 3,
              let percentageRange = Range(match.range(at: 1), in: line),
              let categoryRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let percentageText = String(line[percentageRange]).replacingOccurrences(of: ",", with: ".")
        guard let percentage = Double(percentageText), percentage > 0, percentage <= 100 else {
            return nil
        }

        let categoryName = normalizeCategoryName(String(line[categoryRange]))
        guard !categoryName.isEmpty else { return nil }
        return (percentage, categoryName)
    }

    private static func parseTrailingCashbackLine(_ line: String) -> (Double, String)? {
        let pattern = #"^(.+?)\s+(?:[^\d]{0,8}\s*)?(\d{1,3}(?:[.,]\d{1,2})?)\s*(?:%|％|°/o|°/о|o/o|о/о)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 3,
              let categoryRange = Range(match.range(at: 1), in: line),
              let percentageRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let percentageText = String(line[percentageRange]).replacingOccurrences(of: ",", with: ".")
        guard let percentage = Double(percentageText), percentage > 0, percentage <= 100 else {
            return nil
        }

        let categoryName = normalizeCategoryName(String(line[categoryRange]))
        guard !categoryName.isEmpty else { return nil }
        return (percentage, categoryName)
    }

    private static func parsePercentageOnlyLine(_ line: String) -> Double? {
        let pattern = #"^(?:[^\d]{0,8}\s*)?(?:до\s*)?(\d{1,3}(?:[.,]\d{1,2})?)\s*(?:%|％|°/o|°/о|o/o|о/о)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let percentageRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let percentageText = String(line[percentageRange]).replacingOccurrences(of: ",", with: ".")
        guard let percentage = Double(percentageText), percentage > 0, percentage <= 100 else {
            return nil
        }
        return percentage
    }

    private static func normalizeLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "％", with: "%")
            .replacingOccurrences(of: "°/o", with: "%")
            .replacingOccurrences(of: "°/о", with: "%")
            .replacingOccurrences(of: "o/o", with: "%")
            .replacingOccurrences(of: "о/о", with: "%")
            .replacingOccurrences(of: "O/O", with: "%")
            .replacingOccurrences(of: "О/О", with: "%")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeCategoryName(_ value: String) -> String {
        var normalized = normalizeLine(value)
        normalized = normalized.replacingOccurrences(of: #"^[\-•·:;,.!?]+"#, with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"[;:,.!?]+$"#, with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\s+i$"#, with: "", options: [.regularExpression, .caseInsensitive])
        normalized = normalizeLine(normalized)
        return normalized
    }

    private static func deduplicateKeepingMaxPercentage(
        _ items: [CashbackScreenshotImportItem]
    ) -> [CashbackScreenshotImportItem] {
        var result: [CashbackScreenshotImportItem] = []
        var indexByNormalizedCategory: [String: Int] = [:]

        for item in items {
            let normalizedCategory = item.categoryName.lowercased()
            if let existingIndex = indexByNormalizedCategory[normalizedCategory] {
                let existing = result[existingIndex]
                if item.percentage > existing.percentage {
                    result[existingIndex] = item
                }
                continue
            }

            indexByNormalizedCategory[normalizedCategory] = result.count
            result.append(item)
        }

        return result
    }
}
