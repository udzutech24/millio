//
//  DashboardEditView.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import SwiftUI

struct DashboardEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configs: [DashboardWidgetConfig]

    let onSave: ([DashboardWidgetConfig]) -> Void

    init(configs: [DashboardWidgetConfig], onSave: @escaping ([DashboardWidgetConfig]) -> Void) {
        _configs = State(initialValue: DashboardLayoutStore.normalize(configs))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(MainLocalization.text(MainLocalization.dashboardEditSubtitle))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .listRowBackground(Color.clear)
                }

                Section(MainLocalization.text(MainLocalization.dashboardEditWidgetsSection)) {
                    ForEach(configs.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(titleText(for: configs[index].kind))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)

                                Text(subtitleText(for: configs[index].kind))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            Toggle("", isOn: $configs[index].isVisible)
                                .labelsHidden()
                                .tint(AppColors.brandPrimary)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.black.opacity(0.3))
                    }
                    .onMove(perform: move)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GradientBackground())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(MainLocalization.text(MainLocalization.dashboardEditClose)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(MainLocalization.text(MainLocalization.dashboardEditTitle))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .foregroundStyle(AppColors.brandPrimary)
                }
            }
            .onDisappear {
                onSave(DashboardLayoutStore.normalize(configs))
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        configs.move(fromOffsets: source, toOffset: destination)
        configs = DashboardLayoutStore.normalize(configs)
    }

    private func titleText(for kind: DashboardWidgetKind) -> String {
        MainLocalization.dashboardWidgetTitle(for: kind)
    }

    private func subtitleText(for kind: DashboardWidgetKind) -> String {
        MainLocalization.dashboardWidgetSubtitle(for: kind)
    }
}
