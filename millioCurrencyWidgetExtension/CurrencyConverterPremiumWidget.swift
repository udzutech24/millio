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
    let sourceCode: String
    let valueText: String

    var id: String { sourceCode }
}

private struct CurrencyConverterWidgetEntry: TimelineEntry {
    let date: Date
    let primaryCode: String
    let rows: [CurrencyConverterWidgetRow]
    let lastUpdatedAt: Date?
}

private struct CurrencyConverterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrencyConverterWidgetEntry {
        CurrencyConverterWidgetEntry(
            date: Date(),
            primaryCode: "RUB",
            rows: [
                CurrencyConverterWidgetRow(sourceCode: "USD", valueText: "78,54 р"),
                CurrencyConverterWidgetRow(sourceCode: "EUR", valueText: "91,04 р"),
                CurrencyConverterWidgetRow(sourceCode: "TRY", valueText: "2,13 р")
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
        let converter = CurrencyWidgetShared.ConverterSnapshot.load(from: defaults)

        return CurrencyConverterWidgetEntry(
            date: now,
            primaryCode: converter.primaryCode,
            rows: makeRows(converter: converter),
            lastUpdatedAt: converter.lastUpdatedAt
        )
    }

    private func makeRows(converter: CurrencyWidgetShared.ConverterSnapshot) -> [CurrencyConverterWidgetRow] {
        var preferredSources = converter.selectedCodes.filter { $0 != converter.primaryCode }
        if preferredSources.isEmpty {
            preferredSources = ["USD", "EUR", "TRY", "GBP", "JPY", "CNY", "KZT", "RUB"]
                .filter { $0 != converter.primaryCode }
        }

        return preferredSources.prefix(6).map { sourceCode in
            guard
                let converted = CurrencyWidgetShared.convert(
                    amount: 1,
                    from: sourceCode,
                    to: converter.primaryCode,
                    rates: converter.rates
                )
            else {
                return CurrencyConverterWidgetRow(sourceCode: sourceCode, valueText: "—")
            }

            let value = CurrencyWidgetShared.formatValue(converted, maxFractionDigits: 2)
            return CurrencyConverterWidgetRow(
                sourceCode: sourceCode,
                valueText: "\(value) \(String(localized: "widget.converter.ruble_short"))"
            )
        }
    }
}

private struct CurrencyConverterWidgetEntryView: View {
    let entry: CurrencyConverterWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var openConverterURL: URL? {
        CurrencyWidgetShared.deepLinkURL(for: .openConverter)
    }

    var body: some View {
        content
            .widgetURL(openConverterURL)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(hex: "1C253A"), Color(hex: "081332"), Color(hex: "04102B")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            compactWidgetContent(maxRows: 3, rowFontSize: 14, valueFontSize: 15, rowSpacing: 6, padding: 10)
        case .systemMedium:
            compactWidgetContent(maxRows: 3, rowFontSize: 16, valueFontSize: 17, rowSpacing: 7, padding: 12)
        case .systemLarge:
            largeWidgetContent
        default:
            compactWidgetContent(maxRows: 3, rowFontSize: 14, valueFontSize: 15, rowSpacing: 6, padding: 10)
        }
    }

    private func compactWidgetContent(
        maxRows: Int,
        rowFontSize: CGFloat,
        valueFontSize: CGFloat,
        rowSpacing: CGFloat,
        padding: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rowsView(maxRows: maxRows, rowFontSize: rowFontSize, valueFontSize: valueFontSize, rowSpacing: rowSpacing)
            Spacer(minLength: 0)
            widgetActionLink(
                title: String(localized: "widget.converter.add_spend"),
                iconSystemName: "minus.circle.fill",
                colors: [Color(hex: "F43F5E"), Color(hex: "FB7185")],
                action: .addExpense,
                compact: true
            )
        }
        .padding(padding)
    }

    private var largeWidgetContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowsView(maxRows: 6, rowFontSize: 16, valueFontSize: 17, rowSpacing: 5)
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                widgetActionLink(
                    title: String(localized: "widget.converter.expense"),
                    iconSystemName: "minus.circle.fill",
                    colors: [Color(hex: "F43F5E"), Color(hex: "FB7185")],
                    action: .addExpense,
                    compact: true
                )
                widgetActionLink(
                    title: String(localized: "widget.converter.income"),
                    iconSystemName: "plus.circle.fill",
                    colors: [Color(hex: "22C55E"), Color(hex: "4ADE80")],
                    action: .addIncome,
                    compact: true
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func rowsView(maxRows: Int, rowFontSize: CGFloat, valueFontSize: CGFloat, rowSpacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(entry.rows.prefix(maxRows)) { row in
                HStack(spacing: 8) {
                    widgetFlagIcon(for: row.sourceCode)

                    Text(row.sourceCode)
                        .font(.system(size: rowFontSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: family == .systemLarge ? 64 : 52, alignment: .leading)

                    Text(row.valueText)
                        .font(.system(size: valueFontSize, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func widgetActionLink(
        title: String,
        iconSystemName: String,
        colors: [Color],
        action: CurrencyWidgetShared.DeepLinkAction,
        compact: Bool
    ) -> some View {
        Group {
            if let destination = CurrencyWidgetShared.deepLinkURL(for: action) {
                Link(destination: destination) {
                    HStack(spacing: 6) {
                        Image(systemName: iconSystemName)
                            .font(.system(size: compact ? 12 : 14, weight: .bold))
                        Text(title)
                            .font(.system(size: compact ? 12 : 14, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 7 : 11)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func widgetFlagIcon(for code: String) -> some View {
        let size: CGFloat = family == .systemLarge ? 16 : 15
        let resolvedCode = code.uppercased()

        if let assetName = widgetFlagAssetName(for: resolvedCode) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Text(widgetFlagEmoji(for: resolvedCode))
                .font(.system(size: family == .systemLarge ? 16 : 13))
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
