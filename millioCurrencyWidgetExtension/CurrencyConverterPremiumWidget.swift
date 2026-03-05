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
    let isActive: Bool

    var id: String { code }
}

private struct CurrencyConverterWidgetEntry: TimelineEntry {
    let date: Date
    let hasPremiumAccess: Bool
    let activeCode: String
    let inputText: String
    let rows: [CurrencyConverterWidgetRow]
    let lastUpdatedAt: Date?
}

private struct CurrencyConverterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrencyConverterWidgetEntry {
        CurrencyConverterWidgetEntry(
            date: Date(),
            hasPremiumAccess: true,
            activeCode: "USD",
            inputText: "1200",
            rows: [
                CurrencyConverterWidgetRow(code: "USD", valueText: "1 200", isActive: true),
                CurrencyConverterWidgetRow(code: "EUR", valueText: "1 104", isActive: false),
                CurrencyConverterWidgetRow(code: "RUB", valueText: "108 000", isActive: false)
            ],
            lastUpdatedAt: Date()
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
        let subscription = CurrencyWidgetShared.SubscriptionSnapshot.load(from: defaults)
        let converter = CurrencyWidgetShared.ConverterSnapshot.load(from: defaults)
        let hasPremiumAccess = subscription.hasPremiumAccess(now: now)

        let rows = hasPremiumAccess
            ? makeRows(converter: converter)
            : []

        return CurrencyConverterWidgetEntry(
            date: now,
            hasPremiumAccess: hasPremiumAccess,
            activeCode: converter.activeCode,
            inputText: converter.inputText,
            rows: rows,
            lastUpdatedAt: converter.lastUpdatedAt
        )
    }

    private func makeRows(converter: CurrencyWidgetShared.ConverterSnapshot) -> [CurrencyConverterWidgetRow] {
        let orderedCodes = [converter.activeCode] + converter.selectedCodes.filter { $0 != converter.activeCode }
        let amount = CurrencyWidgetShared.parseAmount(converter.inputText) ?? 0

        return orderedCodes.map { code in
            if code == converter.activeCode {
                let formatted = CurrencyWidgetShared.formatValue(amount, maxFractionDigits: 4)
                return CurrencyConverterWidgetRow(code: code, valueText: formatted, isActive: true)
            }

            guard
                let converted = CurrencyWidgetShared.convert(
                    amount: amount,
                    from: converter.activeCode,
                    to: code,
                    rates: converter.rates
                )
            else {
                return CurrencyConverterWidgetRow(code: code, valueText: "—", isActive: false)
            }

            let formatted = CurrencyWidgetShared.formatValue(converted, maxFractionDigits: 4)
            return CurrencyConverterWidgetRow(code: code, valueText: formatted, isActive: false)
        }
    }
}

private struct CurrencyConverterPremiumWidgetEntryView: View {
    let entry: CurrencyConverterWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var maxRows: Int {
        switch family {
        case .systemSmall:
            return 3
        case .systemMedium:
            return 5
        default:
            return 3
        }
    }

    var body: some View {
        Group {
            if entry.hasPremiumAccess {
                premiumView
            } else {
                lockedView
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(hex: "101828"), Color(hex: "0B1220")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var premiumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "widget.converter.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text(entry.activeCode)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            ForEach(entry.rows.prefix(maxRows)) { row in
                HStack(spacing: 6) {
                    widgetFlagIcon(for: row.code)

                    Text(row.code)
                        .font(.system(size: 12, weight: row.isActive ? .semibold : .regular))
                        .foregroundStyle(row.isActive ? Color.white : Color.white.opacity(0.85))
                        .frame(width: 32, alignment: .leading)

                    Text(row.valueText)
                        .font(.system(size: 12, weight: row.isActive ? .semibold : .regular))
                        .foregroundStyle(row.isActive ? Color(hex: "7DD3FC") : Color.white.opacity(0.85))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }

            Spacer(minLength: 0)

            if let lastUpdatedAt = entry.lastUpdatedAt {
                Text(
                    String(
                        format: String(localized: "widget.converter.updated_at_format"),
                        lastUpdatedAt.formatted(date: .omitted, time: .shortened)
                    )
                )
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func widgetFlagIcon(for code: String) -> some View {
        let size: CGFloat = 14
        let resolvedCode = code.uppercased()

        if let assetName = widgetFlagAssetName(for: resolvedCode) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Text(widgetFlagEmoji(for: resolvedCode))
                .font(.system(size: 11))
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

        let fallbackByCode = currencyCode.lowercased()
        if widgetHasAsset(named: fallbackByCode) {
            return fallbackByCode
        }

        return nil
    }

    private func widgetCurrencyRegionCode(for currencyCode: String) -> String? {
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

    private var lockedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "FDE68A"))

            Text("Premium")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text(String(localized: "widget.converter.premium_only_message"))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(family == .systemSmall ? 3 : 2)

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

struct CurrencyConverterPremiumWidget: Widget {
    static let kind = "CurrencyConverterPremiumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CurrencyConverterWidgetProvider()) { entry in
            CurrencyConverterPremiumWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.converter.configuration_title"))
        .description(String(localized: "widget.converter.configuration_description"))
        .supportedFamilies([.systemSmall, .systemMedium])
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
