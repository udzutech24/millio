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
    @State private var showPrimaryCurrencySheet = false
    @State private var primaryCurrencySearchText = ""
    
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
                    
                    sectionHeader("Основные")
                    card {
                        VStack(spacing: 16) {
                            NavigationLink {
                                LanguageSelectionView(selectedLanguage: Binding(
                                    get: { appState.selectedLanguage },
                                    set: { appState.selectedLanguage = $0 }
                                ))
                            } label: {
                                settingsRow(iconSystemName: "globe", title: "Язык") {
                                    Text(appState.selectedLanguage.displayName)
                                        .foregroundStyle(AppColors.profileValueAccent)
                                    chevron
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile.languageLink")
                            
                            Button {
                                showPrimaryCurrencySheet = true
                            } label: {
                                settingsRow(iconSystemName: "dollarsign", title: "Валюта") {
                                    Text(appState.primaryCurrencyCode)
                                        .foregroundStyle(AppColors.profileValueAccent)
                                    chevron
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile.primaryCurrencyButton")
                        }
                    }
                    
                    // Premium блок
                    premiumSubscriptionBlock

                    // Settings section
                    VStack(spacing: 20) {
                        sectionHeader("Настройки")
                        card {
                            VStack(spacing: 16) {
                                NavigationLink {
                                    BackupManagementView(router: router)
                                } label: {
                                    settingsRow(iconSystemName: "arrow.clockwise.icloud", title: "Резервное копирование") {
                                        Text(backupStatusText)
                                            .foregroundStyle(AppColors.textTertiary)
                                        chevron
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile.backupLink")
                                
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
                                    settingsRow(iconSystemName: "bell", title: "Ежедневные напоминания") { EmptyView() }
                                }
                                .tint(AppColors.toggleOnGreen)
                                .accessibilityIdentifier("profile.dailyReminderToggle")
                            }
                        }
                        
                        sectionHeader("О приложении")
                        card {
                            settingsRow(iconSystemName: "info.circle", title: "Версия") {
                                Text(appVersion)
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .accessibilityIdentifier("profile.versionRow")
                        }
                        
                        #if DEBUG
                        sectionHeader("Отладка")
                        card {
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
                                settingsRow(iconSystemName: "crown", title: "Премиум доступ") { EmptyView() }
                            }
                            .tint(AppColors.toggleOnGreen)
                            .accessibilityIdentifier("profile.debugPremiumToggle")
                        }
                        #endif
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNameEditSheet) {
            nameEditSheet
        }
        .sheet(isPresented: $showPrimaryCurrencySheet) {
            NavigationStack {
                CurrencyPickerView(
                    allCodes: CurrencySelectionSupport.allCurrencyCodesForPicker,
                    searchText: $primaryCurrencySearchText,
                    selectedCodes: CurrencySelectionSupport.pinnedCurrencyCodes(for: appState.primaryCurrencyCode),
                    onSelect: { code in
                        appState.primaryCurrencyCode = code
                        primaryCurrencySearchText = ""
                        showPrimaryCurrencySheet = false
                    }
                )
                .navigationTitle("Валюта")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Закрыть") {
                            primaryCurrencySearchText = ""
                            showPrimaryCurrencySheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .accessibilityIdentifier("profile.primaryCurrencySheet")
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
                    Text("Привет,")
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
                    TextField("Имя", text: $editedName)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: AppColors.profileCardStrokeGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            lineWidth: 1
                                        )
                                }
                        }
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Имя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let value = name.isEmpty ? "Гость" : name
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
                Spacer()

                // Текст справа
                VStack(alignment: .leading, spacing: 4) {
                    Text("Premium")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Расширенные функции и поддержка")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)

                    HStack(spacing: 4) {
                        Text("Подробнее")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.brandPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.brandPrimary)
                    }
                    .padding(.top, 4)
                }
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
            return "Включено"
        }
        return "Выключено"
    }
    
    private func sectionHeader(_ title: String) -> some View {
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
