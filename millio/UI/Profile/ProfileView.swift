//
//  ProfileView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showNameEditSheet = false
    @State private var editedName = ""

    private var legalLinks: ProfileLegalLinks {
        ProfileLegalLinks.make(for: appState.selectedLanguage)
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    private var profileAvatarImage: UIImage? {
        guard let path = appState.profileAvatarPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Блок приветствия и аватарки
                    profileHeaderBlock
                        .padding(.top, 16)
                    
                    sectionHeader("profile.section.general")
                    card {
                        VStack(spacing: 16) {
                            NavigationLink {
                                LanguageSelectionView(selectedLanguage: Binding(
                                    get: { appState.selectedLanguage },
                                    set: { appState.selectedLanguage = $0 }
                                ))
                            } label: {
                                settingsRow(iconSystemName: "globe", title: "profile.language") {
                                    Text(appState.selectedLanguage.displayName)
                                        .foregroundStyle(AppColors.profileValueAccent)
                                    chevron
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile.languageLink")
                            
                            NavigationLink {
                                PrimaryCurrencySelectionView(primaryCurrencyCode: Binding(
                                    get: { appState.primaryCurrencyCode },
                                    set: { appState.primaryCurrencyCode = $0 }
                                ))
                            } label: {
                                settingsRow(iconSystemName: "dollarsign", title: "profile.currency") {
                                    Text(appState.primaryCurrencyCode)
                                        .foregroundStyle(AppColors.profileValueAccent)
                                    chevron
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile.primaryCurrencyLink")
                        }
                    }
                    
                    // Premium блок
                    premiumSubscriptionBlock

                    // Settings section
                    VStack(spacing: 20) {
                        sectionHeader("profile.section.settings")
                        card {
                            VStack(spacing: 16) {
                                NavigationLink {
                                    BackupManagementView(router: router)
                                } label: {
                                    settingsRow(iconSystemName: "arrow.clockwise.icloud", title: "profile.backup") {
                                        Text(backupStatusText)
                                            .foregroundStyle(AppColors.textTertiary)
                                        chevron
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.backupLink")

                                NavigationLink {
                                    AppSecuritySettingsView()
                                } label: {
                                    settingsRow(iconSystemName: "lock.shield", title: "profile.security") {
                                        Text(appLockStatusText)
                                            .foregroundStyle(AppColors.textTertiary)
                                        chevron
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.appSecurityLink")
                                
                                Toggle(isOn: Binding(
                                    get: { appState.isDailyReminderEnabled },
                                    set: { newValue in
                                        appState.isDailyReminderEnabled = newValue
                                        SettingsManager.shared.isDailyReminderEnabled = newValue
                                        
                                        Task {
                                            await NotificationManager.shared.scheduleDailyReminder(enabled: newValue)
                                        }
                                    }
                                )) {
                                    settingsRow(iconSystemName: "bell", title: "profile.daily_reminders") { EmptyView() }
                                }
                                .tint(AppColors.toggleOnGreen)
                                .accessibilityIdentifier("profile.dailyReminderToggle")
                            }
                        }
                        
                        sectionHeader("profile.section.about")
                        card {
                            VStack(spacing: 16) {
                                settingsRow(iconSystemName: "info.circle", title: "profile.version") {
                                    Text(appVersion)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                .accessibilityIdentifier("profile.versionRow")

                                Link(destination: legalLinks.privacyURL) {
                                    legalSettingsRow(iconSystemName: "hand.raised", title: legalLinks.privacyTitle) {
                                        chevron
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.privacyPolicyLink")

                                Link(destination: legalLinks.termsURL) {
                                    legalSettingsRow(iconSystemName: "doc.text", title: legalLinks.termsTitle) {
                                        chevron
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.termsOfUseLink")
                            }
                        }
                        
                        sectionHeader("profile.section.debug")
                        card {
                            VStack(spacing: 16) {
                                Toggle(isOn: Binding(
                                    get: { appState.isPro },
                                    set: { newValue in
                                        if newValue {
                                            SubscriptionManager.shared.grantDebugPremium()
                                        } else {
                                            SubscriptionManager.shared.revokeDebugPremium()
                                        }
                                        appState.subscriptionStatus = SubscriptionManager.shared.status
                                        appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
                                        appState.isTrialActive = SubscriptionManager.shared.isTrialActive
                                    }
                                )) {
                                    settingsRow(iconSystemName: "crown", title: "profile.premium_access") { EmptyView() }
                                }
                                .tint(AppColors.toggleOnGreen)
                                .accessibilityIdentifier("profile.debugPremiumToggle")

                                Button {
                                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                                    appState.lifecycle = .onboarding
                                } label: {
                                    settingsRow(iconSystemName: "sparkles", title: "profile.show_onboarding") {
                                        chevron
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.debugOnboardingButton")
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("profile.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNameEditSheet) {
            nameEditSheet
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                guard let newItem else { return }
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    _ = ProfileAvatarStorage.saveAvatar(imageData: data)
                    appState.profileAvatarPath = SettingsManager.shared.profileAvatarFilePath
                }
            }
        }
        .task {
            // Обновляем статус подписки при открытии профиля
            await SubscriptionManager.shared.checkSubscriptionStatus()
            appState.subscriptionStatus = SubscriptionManager.shared.status
            appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
            appState.isTrialActive = SubscriptionManager.shared.isTrialActive
        }
    }
    
    // MARK: - Profile Header Block
    
    private var profileHeaderBlock: some View {
        HStack(alignment: .center, spacing: 20) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
                avatarView
            }
            .buttonStyle(.plain)
            
            Button {
                editedName = appState.profileDisplayName
                showNameEditSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("profile.greeting")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(appState.profileDisplayName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .accessibilityIdentifier("profile.header")
    }
    
    private var avatarView: some View {
        let size: CGFloat = 72
        return Group {
            if let uiImage = profileAvatarImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("user")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.accentDarkBlue)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: AppColors.profileCardStrokeGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0
                )
        }
        
    }
    
    private var nameEditSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                VStack(spacing: 20) {
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                        TextField("profile.name", text: $editedName)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("profile.name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("profile.done") {
                        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let value = name.isEmpty ? SettingsManager.defaultProfileDisplayName : name
                        SettingsManager.shared.profileDisplayName = value
                        appState.profileDisplayName = value
                        showNameEditSheet = false
                    }
                }
            }
        }
    }
    
    // MARK: - Premium Subscription Block

    private var premiumSubscriptionBlock: some View {
        Button {
            router.push(.subscription)
        } label: {
            HStack(spacing: 0) {
                // Фиксируем позицию текста, чтобы она не "плавала" от длины локализации.
                VStack(alignment: .leading, spacing: 4) {
                    Text("profile.premium.title")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("profile.premium.subtitle")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)

                    HStack(spacing: 4) {
                        Text("profile.premium.details")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.brandPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.brandPrimary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 72)
                .padding(.trailing, 24)
            }
            .frame(height: 90)
           
            .background {
                // Градиентный фон
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.premiumGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(0.8)
            }
            .overlay {
                // Градиентная рамка
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: AppColors.premiumGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .leading) {
                // Корона выезжает за блок влево
                Image("crown")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .offset(x: -50)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 70)
        .padding(.trailing, 20)
    }
    
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.textTertiary)
    }
    
    private var backupStatusText: String {
        if appState.isBackupEnabled {
            if let backupDate = appState.lastBackupDate {
                return backupDate.formatted(date: .abbreviated, time: .shortened)
            }
            return String(localized: "profile.status.enabled", locale: appState.selectedLanguage.locale ?? Locale.current)
        }
        return String(localized: "profile.status.disabled", locale: appState.selectedLanguage.locale ?? Locale.current)
    }

    private var appLockStatusText: String {
        let locale = appState.selectedLanguage.locale ?? Locale.current
        return appState.isAppLockEnabled
            ? String(localized: "profile.status.enabled", locale: locale)
            : String(localized: "profile.status.disabled", locale: locale)
    }
    
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppColors.textPrimary.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }
    
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.profileCardBackgroundGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.profileCardStrokeGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                   
            }
            .padding(.horizontal, 20)
    }
    
    private func settingsRow<Trailing: View>(
        iconSystemName: String,
        title: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 22, alignment: .leading)
            
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            HStack(spacing: 6) {
                trailing()
            }
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    private func legalSettingsRow<Trailing: View>(
        iconSystemName: String,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 22, alignment: .leading)

            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            HStack(spacing: 6) {
                trailing()
            }
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        ProfileView(router: AppRouter())
            .environment(AppState())
    }
}
