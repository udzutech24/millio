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
                    
                    // Premium блок
                    premiumSubscriptionBlock

                    // Settings section
                    VStack(spacing: 20) {
                        
                        VStack(spacing: 16) {
                            Section(content: {
                                NavigationLink {
                                    BackupManagementView(router: router)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text("Резервное копирование")
                                            .foregroundStyle(AppColors.textPrimary)
                                        
                                        Spacer()
                                        
                                        if appState.isBackupEnabled {
                                            if let backupDate = appState.lastBackupDate {
                                                Text(backupDate.formatted(date: .abbreviated, time: .shortened))
                                                    .foregroundStyle(AppColors.textTertiary)
                                            } else {
                                                Text("Включено")
                                                    .foregroundStyle(AppColors.textTertiary)
                                            }
                                        } else {
                                            Text("Выключено")
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                }
                                
                                Toggle("Ежедневные напоминания", isOn: Binding(
                                    get: { appState.isDailyReminderEnabled },
                                    set: { newValue in
                                        appState.isDailyReminderEnabled = newValue
                                        SettingsManager.shared.isDailyReminderEnabled = newValue
                                        
                                        Task {
                                            await NotificationManager.shared.scheduleDailyReminder(enabled: newValue)
                                        }
                                    }
                                ))
                                .tint(.blue)
                            }, header: {
                                Text("Настройки")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            })
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                        }
                        .padding(.horizontal, 24)
                        
                        // Language selection
                        VStack(spacing: 16) {
                            Section(content: {
                                NavigationLink {
                                    LanguageSelectionView(selectedLanguage: Binding(
                                        get: { appState.selectedLanguage },
                                        set: { appState.selectedLanguage = $0 }
                                    ))
                                } label: {
                                    HStack {
                                        Text("Язык")
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        Text(appState.selectedLanguage.displayName)
                                            .foregroundStyle(AppColors.textTertiary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                }
                            }, header: {
                                Text("Язык и регион")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            })
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                        }
                        .padding(.horizontal, 24)
                        
                        // App info
                        VStack(spacing: 16) {
                            Section(content: {
                                HStack {
                                    Text("Версия")
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    Text(appVersion)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }, header: {
                                Text("О приложении")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            })
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                        }
                        .padding(.horizontal, 24)
                        
                        #if DEBUG
                        // Debug section
                        VStack(spacing: 16) {
                            Section(content: {
                                Toggle("Премиум доступ", isOn: Binding(
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
                                ))
                                .tint(.blue)
                            }, header: {
                                Text("Отладка")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            })
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                        }
                        .padding(.horizontal, 24)
                        #endif
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
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
                    Text("Привет,")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(appState.profileDisplayName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
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
    }
    
    private var nameEditSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                VStack(spacing: 20) {
                    TextField("Имя", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
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
                // Шум (noise effect)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ProfileView(router: AppRouter())
            .environment(AppState())
    }
}
