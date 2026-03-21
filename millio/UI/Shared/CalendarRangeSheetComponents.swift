//
//  CalendarRangeSheetComponents.swift
//  millio
//

import SwiftUI

enum CalendarRangePickerDefaults {
    /// New range selection should begin with the leading bound because choosing
    /// "from" first matches the dominant mental model for a custom period.
    static let initialEndpoint: CalendarRangeSelectionEndpoint = .start
}

struct CalendarRangePickerPanel: View {
    let title: String?
    let subtitle: String?
    @Binding var startDate: Date
    @Binding var endDate: Date
    var theme: CalendarRangeTheme = .neutral
    var highlightsSingleDaySelection: Bool = true
    var initialActiveEndpoint: CalendarRangeSelectionEndpoint = CalendarRangePickerDefaults.initialEndpoint
    @State private var activeEndpoint: CalendarRangeSelectionEndpoint = CalendarRangePickerDefaults.initialEndpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if (title?.isEmpty == false) || (subtitle?.isEmpty == false) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 24, weight: .semibold))
                            .lineSpacing(2)
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            HStack(spacing: 10) {
                endpointCard(
                    title: SmartDataResetL10n.periodFrom(locale: .autoupdatingCurrent),
                    date: startDate,
                    endpoint: .start
                )

                endpointCard(
                    title: SmartDataResetL10n.periodTo(locale: .autoupdatingCurrent),
                    date: endDate,
                    endpoint: .end
                )
            }

            CalendarRangeMonthView(
                startDate: $startDate,
                endDate: $endDate,
                activeEndpoint: $activeEndpoint,
                theme: theme,
                highlightsSingleDaySelection: highlightsSingleDaySelection
            )
        }
        .onAppear {
            // Opening on the leading bound keeps the first tap aligned with
            // "choose the period start" across all custom-range entry points.
            activeEndpoint = initialActiveEndpoint
        }
        .onChange(of: startDate) { _, _ in
            if startDate > endDate {
                activeEndpoint = .end
            }
        }
        .onChange(of: endDate) { _, _ in
            if endDate < startDate {
                activeEndpoint = .start
            }
        }
    }

    private func endpointCard(
        title: String,
        date: Date,
        endpoint: CalendarRangeSelectionEndpoint
    ) -> some View {
        let isActive = activeEndpoint == endpoint

        return Button {
            activeEndpoint = endpoint
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text(endpointDateFormatter.string(from: date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isActive ? 0.08 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isActive ? theme.ringColor.opacity(0.95) : Color.white.opacity(0.12),
                                lineWidth: isActive ? 1.4 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private let endpointDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
    return formatter
}()

struct CalendarRangeSheetActionBar: View {
    let secondaryTitle: String
    let primaryTitle: String
    var theme: CalendarRangeTheme = .neutral
    let secondaryAction: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: secondaryAction) {
                Text(secondaryTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.03))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.03))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.68),
                    Color.black.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}
