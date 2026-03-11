//
//  ProfileView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import PhotosUI
import StoreKit

struct ProfileView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showNameEditSheet = false
    @State private var editedName = ""
    @State private var showQuickSetupSheet = false
    @State private var showContactSheet = false
    @State private var showDebugUnlockSheet = false
    @State private var versionTapGate = MultiTapGate(
        targetCount: DebugMenuAccessPolicy.unlockTapCount,
        resetInterval: DebugMenuAccessPolicy.unlockTapResetInterval
    )

    private enum ProfileLayout {
        static let contentHorizontalInset: CGFloat = 20
        static let sectionSpacing: CGFloat = 18
        static let cardCornerRadius: CGFloat = 22
    }

    private let accountDetailsTitle = String(localized: "profile.auth.details", defaultValue: "Details", comment: "Account details entry button title")

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

    private var profileHeaderDisplayName: String {
        ProfileDisplayNameResolver.headerDisplayName(
            storedDisplayName: appState.profileDisplayName,
            authUser: authManager.currentUser
        )
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: ProfileLayout.sectionSpacing) {
                    profileHeaderBlock
                        .padding(.top, 10)

                    if !authManager.isAuthenticated {
                        card {
                            ProfileAuthSection()
                        }
                    }
                    
                    sectionHeader(displayTitle(for: .general))
                    card {
                        sectionContent(for: .general)
                    }
                    
                    premiumSubscriptionBlock

                    VStack(spacing: ProfileLayout.sectionSpacing) {
                        ForEach(secondarySections) { section in
                            sectionHeader(displayTitle(for: section.id))
                            card {
                                sectionContent(for: section.id)
                            }

                            if section.id == .contacts {
                                card {
                                    RateAppBlock(
                                        canOpenAppStoreReview: AppStoreReviewLink.url != nil,
                                        onRateInAppStore: openAppStoreReview,
                                        onSendFeedback: sendFeedback
                                    )
                                }
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
        .sheet(isPresented: $showContactSheet) {
            SupportContactSheet()
        }
        .sheet(isPresented: $showDebugUnlockSheet) {
            DebugMenuUnlockSheet(onUnlockAttempt: { password in
                let isValid = DebugMenuAccessPolicy.validate(password: password)
                if isValid {
                    appState.isDebugMenuUnlocked = true
                }
                return isValid
            })
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
            if authManager.isAuthenticated {
                await authManager.reloadCurrentUser()
            }
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
            
            VStack(alignment: .leading, spacing: 8) {
                Text("profile.greeting")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)

                HStack(alignment: .center, spacing: 12) {
                    Button {
                        editedName = profileHeaderDisplayName
                        showNameEditSheet = true
                    } label: {
                        Text(profileHeaderDisplayName)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)

                    if authManager.isAuthenticated {
                        NavigationLink {
                            ProfileAccountDetailsView()
                        } label: {
                            Text(accountDetailsTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.profileValueAccent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppColors.accentDarkBlue.opacity(0.32))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(AppColors.textTertiary.opacity(0.28), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.headerAccountDetailsLink")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ProfileLayout.contentHorizontalInset)
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
                    lineWidth: 1
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
    
    // MARK: - PRO Subscription Block

    private var premiumSubscriptionBlock: some View {
        Button {
            router.push(.subscription)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.10))

                    Image("crown")
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
                .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 4) {
                    Text("profile.premium.title")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text("profile.premium.subtitle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)

                    Text(premiumStatusLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.isPro ? AppColors.textPrimary : AppColors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("profile.premium.details")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .background {
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
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ProfileLayout.contentHorizontalInset)
    }
    
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.textTertiary)
    }
    
    private var backupStatusText: String {
        let locale = appState.selectedLanguage.locale ?? Locale.current
        if appState.isBackupEnabled {
            if let backupDate = appState.lastBackupDate {
                return backupDate.formatted(date: .abbreviated, time: .shortened)
            }
            return AppLocalization.string("profile.status.enabled", locale: locale)
        }
        return AppLocalization.string("profile.status.disabled", locale: locale)
    }

    private var appLockStatusText: String {
        let locale = appState.selectedLanguage.locale ?? Locale.current
        return appState.isAppLockEnabled
            ? AppLocalization.string("profile.status.enabled", locale: locale)
            : AppLocalization.string("profile.status.disabled", locale: locale)
    }

    private var quickSetupStatusText: String {
        let locale = appState.selectedLanguage.locale ?? Locale.current
        return SettingsManager.shared.isQuickSetupCompleted
            ? AppLocalization.string("profile.status.completed", locale: locale)
            : AppLocalization.string("profile.status.not_completed", locale: locale)
    }

    private var premiumStatusLine: String {
        let locale = appState.selectedLanguage.locale ?? Locale.current
        switch appState.subscriptionAccessSource {
        case .free:
            return AppLocalization.string("profile.premium.status.free", locale: locale)
        case .trial:
            return AppLocalization.string("profile.premium.status.trial", locale: locale)
        case .subscription:
            return AppLocalization.string("profile.premium.status.subscription", locale: locale)
        case .debug:
            return AppLocalization.string("profile.premium.status.debug", locale: locale)
        }
    }

    private var premiumDiagnosticsSummary: String {
        let items = EntitlementDiagnostics.items(for: appState)
        let activeCount = items.filter(\.isPremiumActive).count
        let locale = appState.selectedLanguage.locale ?? Locale.current
        let format = AppLocalization.string("profile.premium.diagnostics.summary", locale: locale)
        return String(format: format, locale: locale, activeCount, items.count)
    }

    private var premiumDiagnosticsTitleKey: LocalizedStringKey {
        "profile.premium.diagnostics.title"
    }

    private var secondarySections: [ProfileMenuSection] {
        ProfileMenuStructure.sections.filter { section in
            guard section.id != .general else { return false }
            if section.id == .debug {
                return appState.isDebugMenuUnlocked
            }
            return true
        }
    }

    @ViewBuilder
    private func sectionContent(for sectionID: ProfileMenuSectionID) -> some View {
        let items = ProfileMenuStructure.sections.first { $0.id == sectionID }?.items ?? []

        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                profileMenuRow(for: item)
                    .padding(.vertical, 12)

                if index < items.count - 1 {
                    FinancesRowDivider(leadingPadding: 34)
                }
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
                            Label(mode.profileTitle(locale: appState.selectedLanguage.locale ?? Locale.current), systemImage: "checkmark")
                        } else {
                            Text(mode.profileTitle(locale: appState.selectedLanguage.locale ?? Locale.current))
                        }
                    }
                }
            } label: {
                settingsRow(iconSystemName: "sparkles.tv", title: "profile.launch_splash.title") {
                    Text(appState.launchSplashDisplayMode.profileTitle(locale: appState.selectedLanguage.locale ?? Locale.current))
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
                settingsRow(iconSystemName: "questionmark.circle", title: "profile.faq.title") {
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
                    title: "profile.smart_data_reset",
                    titleColor: AppColors.error,
                    iconColor: AppColors.error
                ) {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.smartDataResetLink")

        case .version:
            Button {
                handleVersionTap()
            } label: {
                settingsRow(iconSystemName: "info.circle", title: "profile.version") {
                    Text(appVersion)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)
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

        case .contactUs:
            Button {
                showContactSheet = true
            } label: {
                settingsRow(iconSystemName: "message", title: "profile.contact_us") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.contactUsLink")

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

        case .trialDisabled:
            Toggle(isOn: Binding(
                get: { appState.hasTrialDisabledOverride },
                set: { newValue in
                    Task { @MainActor in
                        SubscriptionManager.shared.setTrialDisabledOverride(newValue)
                        await SubscriptionManager.shared.checkSubscriptionStatus()
                        appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)
                    }
                }
            )) {
                settingsRow(iconSystemName: "pause.circle", title: "profile.trial_disabled") { EmptyView() }
            }
            .tint(AppColors.toggleOnGreen)
            .accessibilityIdentifier("profile.trialDisabledToggle")

        case .premiumDiagnostics:
            NavigationLink {
                ProfilePremiumDiagnosticsView()
            } label: {
                settingsRow(iconSystemName: "flag", title: premiumDiagnosticsTitleKey) {
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

    private func sendFeedback() {
        showContactSheet = true
    }

    private func handleVersionTap() {
        guard !appState.isDebugMenuUnlocked else { return }

        var gate = versionTapGate
        if gate.registerTap() {
            showDebugUnlockSheet = true
        }
        versionTapGate = gate
    }

    private func openAppStoreReview() {
        if let url = AppStoreReviewLink.url {
            openURL(url)
            return
        }
        requestReview()
    }
    
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary.opacity(0.46))
            .textCase(.uppercase)
            .kerning(0.25)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ProfileLayout.contentHorizontalInset)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary.opacity(0.46))
            .textCase(.uppercase)
            .kerning(0.25)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ProfileLayout.contentHorizontalInset)
    }
    
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: ProfileLayout.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.profileCardBackgroundGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: ProfileLayout.cardCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.profileCardStrokeGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }
                   
            }
            .clipShape(RoundedRectangle(cornerRadius: ProfileLayout.cardCornerRadius, style: .continuous))
            .padding(.horizontal, ProfileLayout.contentHorizontalInset)
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
        .frame(minHeight: 32)
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
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    private func displayTitle(for sectionID: ProfileMenuSectionID) -> String {
        AppLocalization.string(
            sectionID.localizationKey,
            locale: appState.selectedLanguage.locale ?? Locale.current,
            fallback: sectionID.fallbackTitle
        )
    }
}

private struct SupportContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let channels = SupportContactChannel.allCases
    private let resolver = SupportContactResolver(config: .default)

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 16) {
                    SupportContactHeaderView()

                    FinancesGlassCard(contentPadding: EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)) {
                        VStack(spacing: 0) {
                            ForEach(channels) { channel in
                                Button {
                                    if let url = resolver.url(for: channel) {
                                        openURL(url)
                                    }
                                    dismiss()
                                } label: {
                                    contactRow(for: channel)
                                }
                                .buttonStyle(.plain)

                                if channel != channels.last {
                                    FinancesRowDivider(leadingPadding: 40)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("profile.contact_us")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("profile.done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func contactRow(for channel: SupportContactChannel) -> some View {
        HStack(spacing: 12) {
            SupportContactIconView(icon: channel.icon)
                .frame(width: 24, height: 24)

            Text(channel.titleKey)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct SupportContactHeaderView: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColors.brandPrimary.opacity(0.16))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.brandPrimary.opacity(0.35), lineWidth: 1)

                Image(systemName: "message.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .frame(width: 56, height: 56)
            .shadow(color: AppColors.profileCardGlow, radius: 18, x: 0, y: 10)

            Text("profile.contact.header.title")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text("profile.contact.feedback_message")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

enum SupportContactChannel: String, Identifiable, CaseIterable {
    case email
    case telegram
    case whatsapp

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .email:
            return "profile.contact.option.email"
        case .telegram:
            return "profile.contact.option.telegram"
        case .whatsapp:
            return "profile.contact.option.whatsapp"
        }
    }

    var icon: SupportContactIcon {
        switch self {
        case .email:
            return .system("envelope.fill")
        case .telegram:
            return .asset(name: SupportContactConfig.default.telegramIconAssetName, fallbackSystemName: "paperplane.fill")
        case .whatsapp:
            return .asset(name: SupportContactConfig.default.whatsappIconAssetName, fallbackSystemName: "phone.fill")
        }
    }
}

enum SupportContactIcon {
    case system(String)
    case asset(name: String, fallbackSystemName: String)
}

private struct SupportContactIconView: View {
    let icon: SupportContactIcon

    var body: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
        case .asset(let name, let fallback):
            if let image = UIImage(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

struct SupportContactConfig {
    let emailAddress: String
    let telegramHandle: String
    let whatsappNumber: String
    let telegramIconAssetName: String
    let whatsappIconAssetName: String

    // Replace with real contacts + asset names before release.
    static let `default` = SupportContactConfig(
        emailAddress: "support@millio.app",
        telegramHandle: "millio_support",
        whatsappNumber: "15551234567",
        telegramIconAssetName: "telegram",
        whatsappIconAssetName: "whatsapp"
    )
}

struct SupportContactResolver {
    let config: SupportContactConfig

    func url(for channel: SupportContactChannel) -> URL? {
        switch channel {
        case .email:
            return URL(string: "mailto:\(config.emailAddress)")
        case .telegram:
            return URL(string: "https://t.me/\(config.telegramHandle)")
        case .whatsapp:
            return URL(string: "https://wa.me/\(config.whatsappNumber)")
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView(router: AppRouter())
            .environment(AppState())
    }
}
