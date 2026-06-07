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
    @Environment(\.appRefreshCoordinator) private var appRefreshCoordinator
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
    @State private var rateBlockDismissed = false
    @State private var showSubscriptionSheet = false

    private enum ProfileLayout {
        static let contentHorizontalInset: CGFloat = 20
        static let sectionSpacing: CGFloat = 18
        static let cardCornerRadius: CGFloat = 22
    }

    private var shouldShowRateBlock: Bool {
        guard !rateBlockDismissed, !SettingsManager.shared.hasRatedApp else { return false }
        let twoWeeks: TimeInterval = 14 * 24 * 3600
        return Date().timeIntervalSince(SettingsManager.shared.appFirstLaunchDate) >= twoWeeks
    }

    private var accountDetailsTitle: String {
        L("profile.auth.details", defaultValue: "Details")
    }

    private var legalLinks: ProfileLegalLinks {
        ProfileLegalLinks.make(for: appState.selectedLanguage)
    }

    private var profileLocale: Locale {
        AppLocalization.currentAppLocale
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

                            if section.id == .contacts, shouldShowRateBlock {
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
        .sheet(isPresented: $showSubscriptionSheet) {
            NavigationStack {
                SubscriptionView()
            }
            .environment(appState)
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
            guard let appRefreshCoordinator else { return }
            await appRefreshCoordinator.refreshSubscriptionIfNeeded(
                reason: .profileAppeared,
                appState: appState
            )
            await appRefreshCoordinator.refreshAuthenticatedUserIfNeeded(
                reason: .profileAppeared,
                authManager: authManager
            )
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
                Text(L("profile.greeting"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)

                HStack(alignment: .center, spacing: 10) {
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
                        .padding(.leading, 6)
                    }

                    Spacer(minLength: 0)
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

    @ViewBuilder
    private var premiumSubscriptionBlock: some View {
        switch ProfilePremiumDisplayMode.resolve(for: appState.subscriptionAccessSource) {
        case .promotional:
            ProfilePremiumCard(
                titleKey: "profile.premium.title"
            ) {
                showSubscriptionSheet = true
            }
            .padding(.horizontal, ProfileLayout.contentHorizontalInset)

        case .compact(let status):
            card {
                Button {
                    showSubscriptionSheet = true
                } label: {
                    settingsRow(item: .premiumAccess, title: "profile.premium.title") {
                        rowValueText(compactPremiumStatusText(for: status))
                        chevron
                    }
                }
                .padding(.vertical, 12)
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.premiumCompactLink")
            }
        }
    }
    
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.textTertiary)
    }

    private func iconColor(for item: ProfileMenuItemID) -> Color {
        switch item.iconTone {
        case .blue:
            return AppColors.profileIconBlue
        case .cyan:
            return AppColors.profileIconCyan
        case .green:
            return AppColors.profileIconGreen
        case .orange:
            return AppColors.profileIconOrange
        case .purple:
            return AppColors.profileIconPurple
        case .pink:
            return AppColors.profileIconPink
        case .red:
            return AppColors.profileIconRed
        case .gray:
            return AppColors.profileIconGray
        case .teal:
            return AppColors.profileIconTeal
        }
    }

    private func rowValueText(_ value: String, accent: Bool = false) -> some View {
        Text(value)
            .font(.system(size: 16, weight: accent ? .semibold : .regular))
            .foregroundStyle(accent ? AppColors.profileValueAccent : AppColors.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .allowsTightening(true)
    }
    
    private var backupStatusText: String {
        if appState.isBackupEnabled {
            if let backupDate = appState.lastBackupDate {
                return ProfileBackupStatusFormatter.trailingDateText(
                    for: backupDate,
                    locale: profileLocale
                )
            }
            return AppLocalization.string("profile.status.enabled", locale: profileLocale)
        }
        return AppLocalization.string("profile.status.disabled", locale: profileLocale)
    }

    private var appLockStatusText: String {
        return appState.isAppLockEnabled
            ? AppLocalization.string("profile.status.enabled", locale: profileLocale)
            : AppLocalization.string("profile.status.disabled", locale: profileLocale)
    }

    private var quickSetupStatusText: String {
        return SettingsManager.shared.isQuickSetupCompleted
            ? AppLocalization.string("profile.status.completed", locale: profileLocale)
            : AppLocalization.string("profile.status.not_completed", locale: profileLocale)
    }

    private var remindersRowTitle: String {
        AppLocalization.string(
            "profile.reminders",
            locale: profileLocale,
            fallback: "Reminders"
        )
    }

    private func compactPremiumStatusText(for status: ProfilePremiumCompactStatus) -> String {
        AppLocalization.string(
            status.localizationKey,
            locale: profileLocale
        )
    }

    private var premiumDiagnosticsSummary: String {
        let items = EntitlementDiagnostics.items(for: appState)
        let activeCount = items.filter(\.isPremiumActive).count
        let format = AppLocalization.string("profile.premium.diagnostics.summary", locale: profileLocale)
        return String(format: format, locale: profileLocale, activeCount, items.count)
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
        let items = (ProfileMenuStructure.sections.first { $0.id == sectionID }?.items ?? [])
            .filter(shouldDisplayMenuItem(_:))

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
                settingsRow(item: .language, title: "profile.language") {
                    rowValueText(appState.selectedLanguage.displayName, accent: true)
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
                settingsRow(item: .primaryCurrency, title: "profile.currency") {
                    rowValueText(appState.primaryCurrencyCode, accent: true)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.primaryCurrencyLink")

        case .rateSource:
            NavigationLink {
                RateSourcePickerView()
            } label: {
                settingsRow(item: .rateSource, title: "profile.rate_source") {
                    rowValueText(RateSourcePreferenceStore.shared.preferred.title, accent: true)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.rateSourceLink")

        case .backup:
            NavigationLink {
                BackupManagementView(router: router)
            } label: {
                settingsRow(item: .backup, title: "profile.backup") {
                    rowValueText(backupStatusText)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.backupLink")

        case .googleSheets:
            NavigationLink {
                SheetsConnectionView()
            } label: {
                settingsRow(item: .googleSheets, title: "sheets.menu.title") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.googleSheetsLink")

        case .security:
            NavigationLink {
                AppSecuritySettingsView()
            } label: {
                settingsRow(item: .security, title: "profile.security") {
                    rowValueText(appLockStatusText)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.appSecurityLink")

        case .dailyReminders:
            NavigationLink {
                DailyReminderSettingsView()
            } label: {
                settingsRowText(item: .dailyReminders, title: remindersRowTitle) {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.dailyReminderLink")

        case .quickSetup:
            Button {
                showQuickSetupSheet = true
            } label: {
                settingsRow(item: .quickSetup, title: "profile.quick_setup") {
                    rowValueText(quickSetupStatusText, accent: true)
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
                            Label(mode.profileTitle(locale: profileLocale), systemImage: "checkmark")
                        } else {
                            Text(mode.profileTitle(locale: profileLocale))
                        }
                    }
                }
            } label: {
                settingsRow(item: .launchSplash, title: "profile.launch_splash.title") {
                    rowValueText(
                        appState.launchSplashDisplayMode.profileTitle(locale: profileLocale),
                        accent: true
                    )
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.launchSplashModeMenu")

        case .faq:
            NavigationLink {
                ProfileFAQView(selectedLanguage: appState.selectedLanguage)
            } label: {
                settingsRow(item: .faq, title: "profile.faq.title") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.faqLink")

        case .smartDataReset:
            NavigationLink {
                SmartDataResetView()
            } label: {
                settingsRow(item: .smartDataReset, title: "profile.smart_data_reset") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.smartDataResetLink")

        case .version:
            Button {
                handleVersionTap()
            } label: {
                settingsRow(item: .version, title: "profile.version") {
                    rowValueText(appVersion)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.versionRow")

        case .privacy:
            Link(destination: legalLinks.privacyURL) {
                legalSettingsRow(item: .privacy, title: legalLinks.privacyTitle) {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.privacyPolicyLink")

        case .terms:
            Link(destination: legalLinks.termsURL) {
                legalSettingsRow(item: .terms, title: legalLinks.termsTitle) {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.termsOfUseLink")

        case .contactUs:
            Button {
                showContactSheet = true
            } label: {
                settingsRow(item: .contactUs, title: "profile.contact_us") {
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
                            await SubscriptionManager.shared.checkSubscriptionStatus(force: true)
                        }

                        appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)
                    }
                }
            )) {
                settingsRow(item: .premiumAccess, title: "profile.premium_access") { EmptyView() }
            }
            .tint(AppColors.toggleOnGreen)
            .accessibilityIdentifier("profile.debugPremiumToggle")

        case .trialDisabled:
            Toggle(isOn: Binding(
                get: { appState.hasTrialDisabledOverride },
                set: { newValue in
                    Task { @MainActor in
                        SubscriptionManager.shared.setTrialDisabledOverride(newValue)
                        await SubscriptionManager.shared.checkSubscriptionStatus(force: true)
                        appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)
                    }
                }
            )) {
                settingsRow(item: .trialDisabled, title: "profile.trial_disabled") { EmptyView() }
            }
            .tint(AppColors.toggleOnGreen)
            .accessibilityIdentifier("profile.trialDisabledToggle")

        case .premiumDiagnostics:
            NavigationLink {
                ProfilePremiumDiagnosticsView()
            } label: {
                settingsRow(item: .premiumDiagnostics, title: premiumDiagnosticsTitleKey) {
                    rowValueText(premiumDiagnosticsSummary, accent: true)
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
                settingsRow(item: .showOnboarding, title: "profile.show_onboarding") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.debugOnboardingButton")

#if DEBUG
        case .adminStats:
            NavigationLink {
                AdminStatsDebugView()
            } label: {
                settingsRow(item: .adminStats, title: "profile.admin_stats") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.adminStatsDebugLink")
#endif
        }
    }

    private func shouldDisplayMenuItem(_ item: ProfileMenuItemID) -> Bool {
#if DEBUG
        if item == .adminStats {
            return authManager.isAuthenticated
        }
#endif
        return true
    }

    private func sendFeedback() {
        SettingsManager.shared.hasRatedApp = true
        rateBlockDismissed = true
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
        SettingsManager.shared.hasRatedApp = true
        rateBlockDismissed = true
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
        item: ProfileMenuItemID,
        title: LocalizedStringKey,
        titleColor: Color = AppColors.textPrimary,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor(for: item))
                .frame(width: 22, alignment: .leading)
            
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            
            Spacer()
            
            HStack(spacing: 6) {
                trailing()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    private func legalSettingsRow<Trailing: View>(
        item: ProfileMenuItemID,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor(for: item))
                .frame(width: 22, alignment: .leading)

            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer()

            HStack(spacing: 6) {
                trailing()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    private func settingsRowText<Trailing: View>(
        item: ProfileMenuItemID,
        title: String,
        titleColor: Color = AppColors.textPrimary,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor(for: item))
                .frame(width: 22, alignment: .leading)

            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer()

            HStack(spacing: 6) {
                trailing()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    private func displayTitle(for sectionID: ProfileMenuSectionID) -> String {
        AppLocalization.string(
            sectionID.localizationKey,
            locale: profileLocale,
            fallback: sectionID.fallbackTitle
        )
    }
}

struct SupportContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let channels = SupportContactChannel.allCases
    private let resolver = SupportContactResolver(config: .default)
    private var locale: Locale {
        AppLocalization.currentAppLocale
    }

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
            .navigationTitle(localized("profile.contact_us", fallback: "Contact us"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("profile.done", fallback: "Done")) {
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

            Text(localized(channel.titleLocalizationKey, fallback: channel.fallbackTitle))
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

    private func localized(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}

private struct SupportContactHeaderView: View {
    private var locale: Locale {
        AppLocalization.currentAppLocale
    }

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

            Text(localized("profile.contact.header.title", fallback: "We're here to help."))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(
                localized(
                    "profile.contact.feedback_message",
                    fallback: "Found a bug or have a strong idea for improvement? Send us a screenshot and a short description. If we confirm the issue or ship the idea, you and your friend will get a 1-year subscription"
                )
            )
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func localized(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}

enum SupportContactChannel: String, Identifiable, CaseIterable {
    case email
    case telegram
    case telegramChannel

    var id: String { rawValue }

    var titleLocalizationKey: String {
        switch self {
        case .email:
            return "profile.contact.option.email"
        case .telegram:
            return "profile.contact.option.telegram"
        case .telegramChannel:
            return "profile.contact.option.telegram_channel"
        }
    }

    var fallbackTitle: String {
        switch self {
        case .email:
            return "Email"
        case .telegram:
            return "Telegram"
        case .telegramChannel:
            return "Telegram-канал"
        }
    }

    var icon: SupportContactIcon {
        switch self {
        case .email:
            return .system("envelope.fill")
        case .telegram:
            return .asset(name: SupportContactConfig.default.telegramIconAssetName, fallbackSystemName: "paperplane.fill")
        case .telegramChannel:
            return .asset(name: SupportContactConfig.default.telegramIconAssetName, fallbackSystemName: "paperplane.fill")
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
    let telegramChannelHandle: String
    let telegramIconAssetName: String

    static let `default` = SupportContactConfig(
        emailAddress: "support@millio.app",
        telegramHandle: "millio_support",
        telegramChannelHandle: "millio_app",
        telegramIconAssetName: "telegram"
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
        case .telegramChannel:
            return URL(string: "https://t.me/\(config.telegramChannelHandle)")
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView(router: AppRouter())
            .environment(AppState())
    }
}
