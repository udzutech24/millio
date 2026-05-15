//
//  CurrencyRatesWidget.swift
//  millio

import SwiftUI

private struct CurrencyRateRow: Identifiable {
    let id = UUID()
    let code: String
    let rate: Double
    let primaryCode: String

    var flag: String { CurrencyFlags.flag(for: code) }

    var formattedRate: String {
        let symbol = MonetaCurrency(rawValue: primaryCode)?.symbol ?? primaryCode
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        if rate >= 100 {
            formatter.maximumFractionDigits = 0
        } else if rate >= 1 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        } else {
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 4
        }
        return (formatter.string(from: NSNumber(value: rate)) ?? "—") + " " + symbol
    }
}

struct CurrencyRatesWidget: View {
    var onTap: (() -> Void)? = nil

    @State private var rows: [CurrencyRateRow] = []
    @State private var isLoading = true

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                if isLoading {
                    skeletonRows
                } else {
                    rateRows
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .task { await loadRates() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text(L("dashboard.currency_rates.title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.30))
        }
    }

    // MARK: - Rate rows

    private var rateRows: some View {
        VStack(spacing: 10) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.flag)
                        .font(.system(size: 22))
                        .frame(width: 30)
                    Text(row.code)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.90))
                    Spacer()
                    Text(row.formattedRate)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
        }
    }

    // MARK: - Skeleton

    private var skeletonRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 28, height: 22)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 14)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 80, height: 14)
                }
            }
        }
    }

    // MARK: - Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            )
    }

    // MARK: - Data

    @MainActor
    private func loadRates() async {
        let primary = SettingsManager.shared.primaryCurrencyCode
        let favorites = SettingsManager.shared.favoriteCurrencyCodes.filter { $0 != primary }
        let fallback = ["USD", "EUR", "CNY", "GBP", "JPY", "TRY"].filter { $0 != primary }

        var codes = favorites
        for fb in fallback where codes.count < 3 && !codes.contains(fb) {
            codes.append(fb)
        }
        codes = Array(codes.prefix(3))

        var result: [CurrencyRateRow] = []
        for code in codes {
            if let rate = await CurrencyRateService.shared.getRate(from: code, to: primary) {
                result.append(CurrencyRateRow(code: code, rate: rate, primaryCode: primary))
            }
        }
        rows = result
        isLoading = false
    }
}
