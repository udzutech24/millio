//
//  RateSourcePickerView.swift
//  millio
//

import SwiftUI

struct RateSourcePickerView: View {
    @StateObject private var viewModel: RateSourcePickerViewModel
    @Environment(AppState.self) private var appState

    private var locale: Locale { AppLocalization.currentAppLocale }

    init(viewModel: RateSourcePickerViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? RateSourcePickerViewModel())
    }

    var body: some View {
        ZStack {
            GradientBackground()
            ScrollView {
                VStack(spacing: AppSpacing.m) {
                    ForEach(viewModel.visibleSources()) { source in
                        sourceCard(source)
                            .onTapGesture {
                                withAnimation(AppAnimation.standard) {
                                    viewModel.selectSource(source)
                                }
                            }
                    }
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.xl)
            }
        }
        .navigationTitle(
            AppLocalization.string("rate_source_picker.navigation_title", locale: locale, fallback: "Rate Source")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await viewModel.loadPreviews() }
    }

    // MARK: - Source Card

    @ViewBuilder
    private func sourceCard(_ source: RateSource) -> some View {
        let isSelected = viewModel.selectedSource == source
        let loadState = viewModel.loadingStates[source] ?? .idle
        let preview = viewModel.previews[source]

        VStack(alignment: .leading, spacing: 0) {
            cardHeader(source: source, isSelected: isSelected, preview: preview, loadState: loadState)

            if loadState == .loading {
                cardSkeleton
            } else if loadState == .failed {
                unavailableRow
            } else if let preview {
                if !preview.rates.isEmpty {
                    FinancesRowDivider(leadingPadding: AppSpacing.l)
                    ratesTable(preview: preview, loadState: loadState)
                }
                if preview.isStale {
                    staleDataBadge
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.10 : 0.06))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AppColors.brandPrimary.opacity(0.6), lineWidth: 1)
                    }
                }
        }
        .animation(AppAnimation.standard, value: isSelected)
        .animation(AppAnimation.standard, value: loadState)
    }

    private func cardHeader(
        source: RateSource,
        isSelected: Bool,
        preview: RatePreview?,
        loadState: RateSourcePickerViewModel.LoadState
    ) -> some View {
        HStack(spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(source.title)
                    .font(Font.millioSubheadlineMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Text(source.subtitle)
                    .font(Font.millioCaptionRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            if let updatedAt = preview?.updatedAt, loadState == .loaded {
                Text(updatedAt, style: .relative)
                    .font(Font.millioMicro)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? AppColors.brandPrimary : Color.white.opacity(0.2),
                        lineWidth: isSelected ? 0 : 1.5
                    )
                    .frame(width: 20, height: 20)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Font.millioHeadline)
                        .foregroundStyle(AppColors.brandPrimary)
                }
            }
        }
        .padding(AppSpacing.l)
    }

    private func ratesTable(preview: RatePreview, loadState: RateSourcePickerViewModel.LoadState) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(preview.rates.enumerated()), id: \.element.code) { _, pair in
                HStack {
                    Text(pair.code)
                        .font(Font.millioCalloutRegular)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    if pair.rate > 0 {
                        Text(CurrencyWidgetShared.formatValue(pair.rate))
                            .font(Font.millioCallout)
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        Text("—")
                            .font(Font.millioCallout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.s)
            }
        }
        .padding(.bottom, AppSpacing.s)
    }

    private var cardSkeleton: some View {
        VStack(spacing: AppSpacing.s) {
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 36, height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 72, height: 12)
                }
                .padding(.horizontal, AppSpacing.l)
            }
        }
        .padding(.vertical, AppSpacing.m)
    }

    private var unavailableRow: some View {
        Text(L("rate_source_picker.unavailable", defaultValue: "Unavailable"))
            .font(Font.millioCalloutRegular)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)
    }

    private var staleDataBadge: some View {
        Text(L("rate_source_picker.stale_data", defaultValue: "Data outdated (>24h)"))
            .font(Font.millioCaption2)
            .foregroundStyle(.orange)
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.s)
    }
}
