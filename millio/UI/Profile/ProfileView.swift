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
    @State private var showQuickSetupSheet = false

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
                        sectionContent(for: .general)
                    }
                    
                    // Premium блок
                    premiumSubscriptionBlock

                    VStack(spacing: 20) {
                        ForEach(secondarySections) { section in
                            sectionHeader(section.id.titleKey)
                            card {
                                sectionContent(for: section.id)
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
        .sheet(isPresented: $showQuickSetupSheet) {
            QuickSetupView(
                appState: appState,
                mode: .settings
            )
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
            appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)
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

                    Text(premiumStatusLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appState.isPro ? AppColors.brandPrimary : AppColors.textPrimary.opacity(0.7))
                        .lineLimit(1)

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

    private var quickSetupStatusText: String {
        let locale = appState.selectedLanguage.locale ?? Locale.current
        return SettingsManager.shared.isQuickSetupCompleted
            ? String(localized: "profile.status.completed", locale: locale)
            : String(localized: "profile.status.not_completed", locale: locale)
    }

    private var premiumStatusLine: String {
        switch appState.subscriptionAccessSource {
        case .free:
            return isRussianInterface ? "Текущий режим: Free" : "Current mode: Free"
        case .trial:
            return isRussianInterface ? "Текущий режим: Триал" : "Current mode: Trial"
        case .subscription:
            return isRussianInterface ? "Текущий режим: Подписка" : "Current mode: Subscription"
        case .debug:
            return isRussianInterface ? "Текущий режим: Debug premium" : "Current mode: Debug premium"
        }
    }

    private var premiumDiagnosticsSummary: String {
        let items = EntitlementDiagnostics.items(for: appState)
        let activeCount = items.filter(\.isPremiumActive).count
        return isRussianInterface
            ? "\(activeCount)/\(items.count) активно"
            : "\(activeCount)/\(items.count) active"
    }

    private var premiumDiagnosticsTitle: String {
        isRussianInterface ? "Диагностика Premium" : "Premium diagnostics"
    }

    private var isRussianInterface: Bool {
        (appState.selectedLanguage.locale ?? Locale.current).identifier.hasPrefix("ru")
    }

    private var secondarySections: [ProfileMenuSection] {
        ProfileMenuStructure.sections.filter { $0.id != .general }
    }

    @ViewBuilder
    private func sectionContent(for sectionID: ProfileMenuSectionID) -> some View {
        let section = ProfileMenuStructure.sections.first { $0.id == sectionID }

        VStack(spacing: 16) {
            ForEach(section?.items ?? []) { item in
                profileMenuRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func profileMenuRow(for item: ProfileMenuItemID) -> some View {
        switch item {
        case .language:
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

        case .primaryCurrency:
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

        case .backup:
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

        case .security:
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

        case .dailyReminders:
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

        case .quickSetup:
            Button {
                showQuickSetupSheet = true
            } label: {
                settingsRow(iconSystemName: "sparkles.rectangle.stack", title: "profile.quick_setup") {
                    Text(quickSetupStatusText)
                        .foregroundStyle(AppColors.profileValueAccent)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.quickSetupLink")

        case .launchSplash:
            Menu {
                ForEach(LaunchSplashDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        appState.launchSplashDisplayMode = mode
                        SettingsManager.shared.launchSplashDisplayMode = mode
                    } label: {
                        if mode == appState.launchSplashDisplayMode {
                            Label(mode.profileTitle, systemImage: "checkmark")
                        } else {
                            Text(mode.profileTitle)
                        }
                    }
                }
            } label: {
                settingsRow(iconSystemName: "sparkles.tv", title: "Launch splash") {
                    Text(appState.launchSplashDisplayMode.profileTitle)
                        .foregroundStyle(AppColors.profileValueAccent)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.launchSplashModeMenu")

        case .faq:
            NavigationLink {
                ProfileFAQView(selectedLanguage: appState.selectedLanguage)
            } label: {
                settingsRow(iconSystemName: "questionmark.circle", title: "FAQ") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.faqLink")

        case .smartDataReset:
            NavigationLink {
                SmartDataResetView()
            } label: {
                settingsRow(
                    iconSystemName: "trash",
                    title: "Smart data reset",
                    titleColor: AppColors.error,
                    iconColor: AppColors.error
                ) {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.smartDataResetLink")

        case .version:
            settingsRow(iconSystemName: "info.circle", title: "profile.version") {
                Text(appVersion)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .accessibilityIdentifier("profile.versionRow")

        case .privacy:
            Link(destination: legalLinks.privacyURL) {
                legalSettingsRow(iconSystemName: "hand.raised", title: legalLinks.privacyTitle) {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.privacyPolicyLink")

        case .terms:
            Link(destination: legalLinks.termsURL) {
                legalSettingsRow(iconSystemName: "doc.text", title: legalLinks.termsTitle) {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.termsOfUseLink")

        case .premiumAccess:
            Toggle(isOn: Binding(
                get: { appState.hasDebugPremiumOverride },
                set: { newValue in
                    Task { @MainActor in
                        if newValue {
                            SubscriptionManager.shared.grantDebugPremium()
                        } else {
                            SubscriptionManager.shared.revokeDebugPremium()
                            await SubscriptionManager.shared.checkSubscriptionStatus()
                        }

                        appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)
                    }
                }
            )) {
                settingsRow(iconSystemName: "crown", title: "profile.premium_access") { EmptyView() }
            }
            .tint(AppColors.toggleOnGreen)
            .accessibilityIdentifier("profile.debugPremiumToggle")

        case .premiumDiagnostics:
            NavigationLink {
                ProfilePremiumDiagnosticsView()
            } label: {
                settingsRow(iconSystemName: "flag", title: LocalizedStringKey(premiumDiagnosticsTitle)) {
                    Text(premiumDiagnosticsSummary)
                        .foregroundStyle(AppColors.profileValueAccent)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.premiumDiagnosticsLink")

        case .showOnboarding:
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
        titleColor: Color = AppColors.textPrimary,
        iconColor: Color = AppColors.textSecondary,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, alignment: .leading)
            
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(titleColor)
            
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
