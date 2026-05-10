//
//  RootTabBar.swift
//  millio
//

import SwiftUI

struct RootTabBar: View {
    @Binding var selectedTab: RootTab
    @Binding var showFABMenu: Bool
    let onFABAction: (FABAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(
                tab: .dashboard,
                icon: "house.fill",
                label: MainLocalization.text(MainLocalization.tabDashboard)
            )

            tabButton(
                tab: .finances,
                icon: "creditcard.fill",
                label: MainLocalization.text(MainLocalization.tabFinances)
            )

            fabButton

            tabButton(
                tab: .dynamics,
                icon: "chart.bar.fill",
                label: MainLocalization.text(MainLocalization.tabDynamics)
            )

            tabButton(
                tab: .cashflow,
                icon: "arrow.left.arrow.right",
                label: MainLocalization.text(MainLocalization.serviceCashflow)
            )
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(glassBackground)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            fabMenuOverlay
                .offset(y: -88)
        }
    }

    // MARK: - FAB Menu Overlay

    private var fabMenuOverlay: some View {
        HStack(spacing: 10) {
            fabPill(
                title: MainLocalization.text(MainLocalization.quickActionIncome),
                action: .income,
                openDelay: 0
            )

            fabPill(
                title: MainLocalization.text(MainLocalization.quickActionExpense),
                action: .expense,
                openDelay: 0.07
            )
        }
        .allowsHitTesting(showFABMenu)
    }

    private func fabPill(title: String, action: FABAction, openDelay: Double) -> some View {
        Button {
            onFABAction(action)
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
                }
                .shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 6)
                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(showFABMenu ? 1 : 0)
        .scaleEffect(showFABMenu ? 1 : 0.55, anchor: .bottom)
        .blur(radius: showFABMenu ? 0 : 4)
        .animation(
            .spring(response: 0.46, dampingFraction: 0.72)
            .delay(showFABMenu ? openDelay : 0),
            value: showFABMenu
        )
    }

    // MARK: - Glass Background

    private var glassBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1)
    }

    // MARK: - Tab Button

    private func tabButton(tab: RootTab, icon: String, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .scaleEffect(isActive ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isActive)
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(
                isActive
                    ? Color.white
                    : Color.white.opacity(0.4)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.70)) {
                showFABMenu.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 50)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .rotationEffect(.degrees(showFABMenu ? 45 : 0))
                    .animation(.spring(response: 0.38, dampingFraction: 0.68), value: showFABMenu)
            }
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
