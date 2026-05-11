//
//  DashboardDeltaPeriodPickerSheet.swift
//  millio

import SwiftUI

struct DashboardDeltaPeriodPickerSheet: View {
    @Binding var selectedPeriod: Int

    private var options: [(days: Int, label: String)] {
        [
            (1,  L("dashboard.period.1day")),
            (3,  L("dashboard.period.3days")),
            (7,  L("dashboard.period.7days")),
            (14, L("dashboard.period.14days")),
            (30, L("dashboard.period.30days")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L("dashboard.period.picker_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.top, 24)
                .padding(.bottom, 20)

            HStack(spacing: 10) {
                ForEach(options, id: \.days) { option in
                    periodChip(option.days, label: option.label)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.08).ignoresSafeArea())
    }

    private func periodChip(_ days: Int, label: String) -> some View {
        let isSelected = days == selectedPeriod
        return Button(action: { selectedPeriod = days }) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}
