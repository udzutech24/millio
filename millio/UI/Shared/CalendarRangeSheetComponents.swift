//
//  CalendarRangeSheetComponents.swift
//  millio
//

import SwiftUI

enum CalendarRangePickerDefaults {
    /// Start-first range selection keeps the interaction deterministic and
    /// avoids the common "why did my previous start date move?" confusion.
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
    var quickPresets: [CalendarRangeQuickPreset] = CalendarRangeQuickPreset.allCases
    @State private var activeEndpoint: CalendarRangeSelectionEndpoint = CalendarRangePickerDefaults.initialEndpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if (title?.isEmpty == false) || (subtitle?.isEmpty == false) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            HStack(spacing: 12) {
                endpointCard(
                    title: CalendarRangePickerCopy.startDateLabel(),
                    date: startDate,
                    endpoint: .start
                )

                endpointCard(
                    title: CalendarRangePickerCopy.endDateLabel(),
                    date: endDate,
                    endpoint: .end
                )
            }

            quickPresetRow

            CalendarRangeMonthView(
                startDate: $startDate,
                endDate: $endDate,
                activeEndpoint: $activeEndpoint,
                theme: theme,
                highlightsSingleDaySelection: highlightsSingleDaySelection
            )
        }
        .onAppear {
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

    private var quickPresetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPresets, id: \.self) { preset in
                    let isSelected = presetMatchesCurrentRange(preset)
                    Button {
                        let range = preset.dateRange(referenceDate: Date())
                        startDate = range.start
                        endDate = range.end
                        activeEndpoint = .end
                    } label: {
                        Text(preset.title())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(theme.softAccentFill) : AnyShapeStyle(Color.white.opacity(0.05)))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(isSelected ? theme.ringColor.opacity(0.82) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
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
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                Text(endpointDateFormatter.string(from: date))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.015))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                isActive ? AnyShapeStyle(theme.accentFill) : AnyShapeStyle(theme.panelStroke),
                                lineWidth: isActive ? 1.25 : 1
                            )
                    )
            )
            .shadow(color: isActive ? theme.ringColor.opacity(0.12) : .clear, radius: 14, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func presetMatchesCurrentRange(_ preset: CalendarRangeQuickPreset) -> Bool {
        let range = preset.dateRange(referenceDate: Date())
        let calendar = Calendar.current
        return calendar.isDate(calendar.startOfDay(for: startDate), inSameDayAs: range.start)
            && calendar.isDate(calendar.startOfDay(for: endDate), inSameDayAs: range.end)
    }
}

private let endpointDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("d MMMM")
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
            actionButton(title: secondaryTitle, style: .secondary, action: secondaryAction)
            actionButton(title: primaryTitle, style: .primary, action: primaryAction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        style: ActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(buttonBackground(style: style))
                .overlay(buttonStroke(style: style))
        }
        .buttonStyle(.plain)
    }

    private func buttonBackground(style: ActionStyle) -> some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(style == .primary ? 0.025 : 0.02))
    }

    private func buttonStroke(style: ActionStyle) -> some View {
        Capsule(style: .continuous)
            .stroke(
                style == .primary ? AnyShapeStyle(theme.accentFill) : AnyShapeStyle(Color.white.opacity(0.14)),
                lineWidth: style == .primary ? 1.4 : 1
            )
    }

    private enum ActionStyle {
        case primary
        case secondary
    }
}
