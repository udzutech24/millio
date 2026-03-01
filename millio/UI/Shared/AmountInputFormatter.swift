//
//  AmountInputFormatter.swift
//  millio
//

import Foundation

enum AmountInputFormatter {
    static func sanitize(_ text: String, maxFractionDigits: Int = 2) -> String {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        var result = ""
        var hasSeparator = false
        var fractionCount = 0

        for ch in normalized {
            if ch.isNumber {
                if hasSeparator {
                    guard fractionCount < maxFractionDigits else { continue }
                    fractionCount += 1
                }
                result.append(ch)
                continue
            }

            if ch == ".", !hasSeparator {
                hasSeparator = true
                if result.isEmpty {
                    result = "0"
                }
                result.append(ch)
            }
        }

        return trimLeadingZeros(result)
    }

    static func parse(_ text: String) -> Double? {
        let normalized = sanitize(text, maxFractionDigits: 8)
        return Double(normalized)
    }

    static func display(_ text: String, maxFractionDigits: Int = 2) -> String {
        let sanitized = sanitize(text, maxFractionDigits: maxFractionDigits)
        guard !sanitized.isEmpty else { return "" }

        let hasDecimalSeparator = sanitized.contains(".")
        let trailingSeparator = sanitized.last == "."
        let number = Double(sanitized) ?? 0

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = 3
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = hasDecimalSeparator ? maxFractionDigits : 0

        var formatted = formatter.string(from: NSNumber(value: number)) ?? sanitized
        if trailingSeparator, !formatted.contains(".") {
            formatted.append(".")
        }
        return formatted
    }

    static func plainString(from value: Double) -> String {
        if value == 0 { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    private static func trimLeadingZeros(_ value: String) -> String {
        guard !value.isEmpty else { return value }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        var integerPart = String(parts[0])
        let fractionPart = parts.count > 1 ? String(parts[1]) : nil

        while integerPart.count > 1 && integerPart.first == "0" {
            integerPart.removeFirst()
        }

        if integerPart.isEmpty {
            integerPart = fractionPart == nil ? "" : "0"
        }

        if let fractionPart {
            return "\(integerPart).\(fractionPart)"
        }
        return integerPart
    }
}
