//
//  AppSecuritySettingsView.swift
//  millio
//
//  Created by Александр Сидоркин on 21.02.2026.
//

import SwiftUI

struct AppSecuritySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreatePinSheet = false
    @State private var showChangePinSheet = false
    @State private var infoText: String?

    private var biometricsTitle: String {
        AppLockBiometricAuth.settingsTitle()
    }

    private var biometricsAvailable: Bool {
        AppLockBiometricAuth.canUseBiometrics()
    }

    private var hasPin: Bool {
        AppLockPinStore.shared.hasPin()
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    FinancesSectionHeader(title: "Безопасность")

                    FinancesGlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: Binding(
                                get: { appState.isAppLockEnabled },
                                set: { newValue in
                                    if newValue {
                                        enablePinProtection()
                                    } else {
                                        appState.isAppLockEnabled = false
                                    }
                                }
                            )) {
                                securityRow(iconSystemName: "lock.fill", title: "PIN-код")
                            }
                            .tint(AppColors.toggleOnGreen)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .disabled(!hasPin && appState.isAppLockEnabled)

                            FinancesRowDivider()

                            Toggle(isOn: Binding(
                                get: { appState.isBiometricUnlockEnabled },
                                set: { appState.isBiometricUnlockEnabled = $0 }
                            )) {
                                securityRow(iconSystemName: AppLockBiometricAuth.settingsIconSystemName(), title: biometricsTitle)
                            }
                            .tint(AppColors.toggleOnGreen)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .disabled(!appState.isAppLockEnabled || !biometricsAvailable)

                            FinancesRowDivider()

                            Button {
                                showChangePinSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "number")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(width: 22, alignment: .leading)
                                    Text("Сменить PIN-код")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasPin)
                        }
                    }

                    if let infoText {
                        Text(infoText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Защита приложения")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCreatePinSheet) {
            AppPinCodeSetupView(mode: .create) {
                appState.isAppLockEnabled = true
                appState.isAppLocked = true
            }
        }
        .sheet(isPresented: $showChangePinSheet) {
            AppPinCodeSetupView(mode: .change, onSaved: {})
        }
        .onAppear {
            if !hasPin, appState.isAppLockEnabled {
                appState.isAppLockEnabled = false
                appState.isBiometricUnlockEnabled = false
            }
            if !biometricsAvailable {
                appState.isBiometricUnlockEnabled = false
                infoText = "На этом устройстве биометрия недоступна."
            } else {
                infoText = nil
            }
        }
    }

    private func enablePinProtection() {
        if hasPin {
            appState.isAppLockEnabled = true
            appState.isAppLocked = true
        } else {
            showCreatePinSheet = true
        }
    }

    private func securityRow(iconSystemName: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 22, alignment: .leading)
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        AppSecuritySettingsView()
            .environment(AppState())
    }
}
