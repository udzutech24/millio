//
//  CurrencyConverterPremiumWidget.swift
//  millioCurrencyWidgetExtension
//
//  Created by Codex on 24.02.2026.
//

import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

private struct CurrencyConverterWidgetRow: Identifiable, Equatable {
    let code: String
    let valueText: String

    var id: String { code }
}

private struct CurrencyConverterWidgetEntry: TimelineEntry {
    let date: Date
    let rows: [CurrencyConverterWidgetRow]
}

private struct CurrencyConverterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrencyConverterWidgetEntry {
        CurrencyConverterWidgetEntry(
            date: Date(),
            rows: [
                CurrencyConverterWidgetRow(code: "USD", valueText: "78,54 ₽"),
                CurrencyConverterWidgetRow(code: "EUR", valueText: "91,04 ₽"),
                CurrencyConverterWidgetRow(code: "TRY", valueText: "2,13 ₽")
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrencyConverterWidgetEntry) -> Void) {
        completion(makeEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrencyConverterWidgetEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(now: now)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry(now: Date) -> CurrencyConverterWidgetEntry {
        let defaults = UserDefaults(suiteName: CurrencyWidgetShared.appGroupID) ?? .standard
        let converter = CurrencyWidgetShared.ConverterSnapshot.load(from: defaults)
        let rows = makeRows(converter: converter)
        return CurrencyConverterWidgetEntry(date: now, rows: rows)
    }

    private func makeRows(converter: CurrencyWidgetShared.ConverterSnapshot) -> [CurrencyConverterWidgetRow] {
        let primary = converter.primaryCode
        var sourceCodes = converter.selectedCodes.filter { $0 != primary }
        if sourceCodes.isEmpty {
            sourceCodes = ["USD", "EUR", "TRY", "GBP", "CNY", "JPY"].filter { $0 != primary }
        }

        let suffix = currencySuffix(for: primary)

        return sourceCodes.prefix(3).map { code in
            guard let converted = CurrencyWidgetShared.convert(amount: 1, from: code, to: primary, rates: converter.rates) else {
                return CurrencyConverterWidgetRow(code: code, valueText: "—")
            }
            let number = CurrencyWidgetShared.formatValue(converted, maxFractionDigits: 2)
            return CurrencyConverterWidgetRow(code: code, valueText: "\(number) \(suffix)")
        }
    }

    private func currencySuffix(for currencyCode: String) -> String {
        let normalized = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let explicitSymbols: [String: String] = [
            "RUB": "₽",
            "USD": "$",
            "EUR": "€",
            "GBP": "£",
            "TRY": "₺",
            "JPY": "¥",
            "CNY": "¥",
            "KZT": "₸"
        ]
        if let explicitSymbol = explicitSymbols[normalized] {
            return explicitSymbol
        }
        let fallback = normalized
        guard !normalized.isEmpty else { return fallback }

        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            if locale.currency?.identifier.uppercased() == normalized {
                if let symbol = locale.currencySymbol, !symbol.isEmpty {
                    return symbol
                }
            }
        }

        return fallback
    }
}

private struct CurrencyConverterWidgetEntryView: View {
    let entry: CurrencyConverterWidgetEntry

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.rows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Spacer(minLength: 0)

                    HStack(spacing: 14) {
                        widgetFlagIcon(for: row.code)

                        Text(row.valueText)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 11)

                if index < entry.rows.count - 1 {
                    Divider()
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.02),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "404553"), Color(hex: "1A1D26"), Color(hex: "0E1118")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Color.white.opacity(0.09), Color.clear],
                    center: .topLeading,
                    startRadius: 4,
                    endRadius: 220
                )

                LinearGradient(
                    colors: [Color(hex: "27456B").opacity(0.14), Color.clear, Color.black.opacity(0.18)],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            }
        }
        .widgetURL(CurrencyWidgetShared.deepLinkURL(for: .openConverter))
    }

    @ViewBuilder
    private func widgetFlagIcon(for code: String) -> some View {
        let size: CGFloat = 32
        let normalized = code.uppercased()
        if let assetName = widgetFlagAssetName(for: normalized) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        } else {
            Text(widgetFlagEmoji(for: normalized))
                .font(.system(size: 26))
                .frame(width: size, height: size)
        }
    }

    private func widgetFlagAssetName(for currencyCode: String) -> String? {
        let explicit: [String: String] = [
            "RUB": "ru",
            "USD": "us",
            "EUR": "eu",
            "KZT": "kz",
            "GBP": "gb",
            "TRY": "tr",
            "JPY": "jp",
            "CNY": "cn"
        ]

        if let explicitRegion = explicit[currencyCode], widgetHasAsset(named: explicitRegion) {
            return explicitRegion
        }

        if let region = widgetCurrencyRegionCode(for: currencyCode), widgetHasAsset(named: region.lowercased()) {
            return region.lowercased()
        }

        return nil
    }

    private func widgetCurrencyRegionCode(for currencyCode: String) -> String? {
        let explicit: [String: String] = [
            "USD": "US",
            "EUR": "EU",
            "RUB": "RU",
            "TRY": "TR",
            "CNY": "CN",
            "GBP": "GB",
            "JPY": "JP",
            "KZT": "KZ"
        ]
        if let region = explicit[currencyCode] {
            return region
        }

        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            if locale.currency?.identifier.uppercased() == currencyCode,
               let region = locale.region?.identifier.uppercased(),
               region.count == 2 {
                return region
            }
        }
        return nil
    }

    private func widgetFlagEmoji(for currencyCode: String) -> String {
        guard let region = widgetCurrencyRegionCode(for: currencyCode) else { return "🏳️" }
        let base: UInt32 = 0x1F1E6
        let a = UnicodeScalar("A").value
        var scalars: [UnicodeScalar] = []
        for scalar in region.unicodeScalars {
            let value = scalar.value
            guard value >= a, value <= UnicodeScalar("Z").value else { return "🏳️" }
            if let regionalIndicator = UnicodeScalar(base + (value - a)) {
                scalars.append(regionalIndicator)
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func widgetHasAsset(named name: String) -> Bool {
#if canImport(UIKit)
        UIImage(named: name) != nil
#else
        false
#endif
    }
}

struct CurrencyConverterWidget: Widget {
    static let kind = "CurrencyConverterPremiumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CurrencyConverterWidgetProvider()) { entry in
            CurrencyConverterWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.converter.configuration_title"))
        .description(String(localized: "widget.converter.configuration_description"))
        .supportedFamilies([.systemSmall])
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        default:
            r = 255
            g = 255
            b = 255
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
