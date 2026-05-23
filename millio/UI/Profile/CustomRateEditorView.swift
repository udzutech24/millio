//
//  CustomRateEditorView.swift
//  millio
//

import SwiftUI

struct CustomRateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let primaryCode: String
    private let favoriteCodes: [String]
    private let onSave: () -> Void

    // Рабочая копия курсов: code → строка TextField
    @State private var rateInputs: [String: String] = [:]

    init(
        primaryCode: String = SettingsManager.shared.primaryCurrencyCode,
        favoriteCodes: [String] = SettingsManager.shared.favoriteCurrencyCodes,
        onSave: @escaping () -> Void = {}
    ) {
        self.primaryCode = primaryCode
        self.favoriteCodes = favoriteCodes
        self.onSave = onSave
    }

    private var locale: Locale { AppLocalization.currentAppLocale }

    // USD обязателен если primary ≠ USD
    private var usdRequired: Bool { primaryCode.uppercased() != "USD" }

    // Все валюты для редактирования: избранные минус primary, плюс USD если нужен
    private var editableCodes: [String] {
        var codes = favoriteCodes.map { $0.uppercased() }.filter { $0 != primaryCode.uppercased() }
        if usdRequired, !codes.contains("USD") {
            codes.insert("USD", at: 0)
        }
        return codes
    }

    private var canSave: Bool {
        guard usdRequired else { return true }
        guard let usdStr = rateInputs["USD"], let val = Double(usdStr.replacingOccurrences(of: ",", with: ".")) else { return false }
        return val > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        if usdRequired {
                            usdRequiredNote
                                .padding(.horizontal, AppSpacing.l)
                                .padding(.top, AppSpacing.m)
                                .padding(.bottom, AppSpacing.s)
                        }
                        ratesList
                    }
                }
            }
            .navigationTitle(
                AppLocalization.string("custom_rate_editor.title", locale: locale, fallback: "Custom Rates")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("custom_rate_editor.cancel", defaultValue: "Отмена")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("custom_rate_editor.save", defaultValue: "Сохранить")) {
                        saveAndDismiss()
                    }
                    .disabled(!canSave)
                    .foregroundStyle(canSave ? AppColors.brandPrimary : AppColors.textSecondary)
                }
            }
        }
        .onAppear { loadExistingRates() }
    }

    // MARK: - Views

    private var usdRequiredNote: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "exclamationmark.circle")
                .font(Font.millioCaptionRegular)
                .foregroundStyle(.orange)
            Text(L("custom_rate_editor.usd_required",
                   defaultValue: "Необходим курс USD для конвертации"))
                .font(Font.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(AppSpacing.m)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var ratesList: some View {
        VStack(spacing: 0) {
            ForEach(editableCodes, id: \.self) { code in
                rateRow(code: code)
                if code != editableCodes.last {
                    FinancesRowDivider(leadingPadding: AppSpacing.l + 28 + AppSpacing.m)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.vertical, AppSpacing.m)
    }

    private func rateRow(code: String) -> some View {
        HStack(spacing: AppSpacing.m) {
            Text(CurrencyFlags.flag(for: code))
                .font(.system(size: 22))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(code)
                    .font(Font.millioCalloutRegular)
                    .foregroundStyle(AppColors.textPrimary)
                if usdRequired && code == "USD" {
                    Text(L("custom_rate_editor.usd_row_hint", defaultValue: "Обязательно"))
                        .font(Font.millioCaption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            TextField("0", text: Binding(
                get: { rateInputs[code] ?? "" },
                set: { rateInputs[code] = $0 }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(Font.millioCallout)
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: 100)

            Text(primaryCode.uppercased())
                .font(Font.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.vertical, AppSpacing.m)
    }

    // MARK: - Logic

    private func loadExistingRates() {
        let stored = CustomRateStore.shared.rates
        for code in editableCodes {
            if let val = stored[code], val > 0 {
                rateInputs[code] = formatForInput(val)
            }
        }
    }

    private func saveAndDismiss() {
        var newRates: [String: Double] = [:]
        for code in editableCodes {
            let str = (rateInputs[code] ?? "").replacingOccurrences(of: ",", with: ".")
            if let val = Double(str), val > 0 {
                newRates[code] = val
            }
        }
        var store = CustomRateStore.shared
        store.rates = newRates
        store.primaryForRates = primaryCode

        if RateSourcePreferenceStore.shared.preferred == .custom {
            CurrencyRateService.shared.setRateSource(.custom)
        }

        onSave()
        dismiss()
    }

    private func formatForInput(_ value: Double) -> String {
        // Без лишних нулей: 71.0 → "71", 71.5 → "71.5"
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.4g", value)
    }
}
