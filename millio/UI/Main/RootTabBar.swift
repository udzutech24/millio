//
//  RootTabBar.swift
//  millio
//

import SwiftUI

struct RootTabBar: View {
    @Binding var selectedTab: RootTab
    let onFABAction: (FABAction) -> Void

    @State private var showFABDialog = false

    var body: some View {
        HStack(spacing: 0) {
            // Дашборд
            tabButton(
                tab: .dashboard,
                icon: "house",
                label: MainLocalization.text(MainLocalization.tabDashboard)
            )

            // Счета
            tabButton(
                tab: .finances,
                icon: "creditcard",
                label: MainLocalization.text(MainLocalization.tabFinances)
            )

            // Динамика
            tabButton(
                tab: .dynamics,
                icon: "chart.line.uptrend.xyaxis",
                label: MainLocalization.text(MainLocalization.tabDynamics)
            )

            // FAB [+]
            fabButton

            // Кэшфлоу
            tabButton(
                tab: .cashflow,
                icon: "arrow.left.arrow.right",
                label: MainLocalization.text(MainLocalization.serviceCashflow)
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            ZStack {
                Color.black.opacity(0.85)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.45)
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .confirmationDialog("", isPresented: $showFABDialog) {
            Button(MainLocalization.text(MainLocalization.quickActionIncome)) { onFABAction(.income) }
            Button(MainLocalization.text(MainLocalization.quickActionExpense)) { onFABAction(.expense) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Tab Button

    private func tabButton(tab: RootTab, icon: String, label: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? Color.white : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button {
            showFABDialog = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.30), lineWidth: 1.2)
                    )

                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}
