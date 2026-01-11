//
//  WaterView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData

struct WaterView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WaterViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                waterContentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WaterViewModel(modelContext: modelContext)
            }
        }
    }
    
    @ViewBuilder
    private func waterContentView(viewModel: WaterViewModel) -> some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Заголовок и прогресс
                    progressSection(viewModel: viewModel)
                    
                    // Быстрые кнопки добавления
                    quickAddButtons(viewModel: viewModel)
                    
                    // Статистика за неделю
                    weeklyStatsSection(viewModel: viewModel)
                    
                    // История за сегодня
                    todayHistorySection(viewModel: viewModel)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Вода")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.showSettings)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showSettings },
            set: { if !$0 { viewModel.handle(.hideSettings) } }
        )) {
            WaterSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showAddWaterDialog },
            set: { if !$0 { viewModel.handle(.hideAddWaterDialog) } }
        )) {
            AddWaterDialog(viewModel: viewModel)
        }
    }
    
    // MARK: - Progress Section
    
    @ViewBuilder
    private func progressSection(viewModel: WaterViewModel) -> some View {
        VStack(spacing: 16) {
            // Круговой прогресс
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: AppColors.waterGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ).opacity(0.3),
                        lineWidth: 16
                    )
                    .frame(width: 200, height: 200)
                
                Circle()
                    .trim(from: 0, to: viewModel.state.progress)
                    .stroke(
                        LinearGradient(
                            colors: AppColors.waterGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.state.progress)
                
                VStack(spacing: 4) {
                    Text("\(viewModel.state.todayAmount)")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("мл")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    Text("из \(viewModel.state.targetAmount) мл")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            // Процент выполнения
            Text("\(Int(viewModel.state.progress * 100))%")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.waterGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .padding(.vertical, 24)
    }
    
    // MARK: - Quick Add Buttons
    
    @ViewBuilder
    private func quickAddButtons(viewModel: WaterViewModel) -> some View {
        VStack(spacing: 12) {
            Text("Быстрое добавление")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                QuickAddButton(amount: 100, icon: "drop.fill", viewModel: viewModel)
                QuickAddButton(amount: 250, icon: "drop.fill", viewModel: viewModel)
                QuickAddButton(amount: 500, icon: "drop.fill", viewModel: viewModel)
                QuickAddButton(amount: 0, icon: "plus", viewModel: viewModel) // Кастомное количество
            }
        }
    }
    
    // MARK: - Weekly Stats
    
    @ViewBuilder
    private func weeklyStatsSection(viewModel: WaterViewModel) -> some View {
        VStack(spacing: 12) {
            Text("Статистика за неделю")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                ForEach(viewModel.state.weeklyStats) { stat in
                    VStack(spacing: 8) {
                        // Бар
                        GeometryReader { geometry in
                            VStack {
                                Spacer()
                                
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: AppColors.waterGradient,
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(height: max(4, CGFloat(stat.amount) / CGFloat(stat.target) * geometry.size.height))
                            }
                        }
                        .frame(height: 100)
                        
                        // День недели
                        Text(dayName(for: stat.date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        // Количество
                        Text("\(stat.amount)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
    
    // MARK: - Today History
    
    @ViewBuilder
    private func todayHistorySection(viewModel: WaterViewModel) -> some View {
        VStack(spacing: 12) {
            Text("Сегодня")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if viewModel.state.todayEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "drop")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("Пока нет записей")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.state.todayEntries) { entry in
                        WaterEntryRow(entry: entry) {
                            viewModel.handle(.deleteEntry(entry))
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "E"
        return formatter.string(from: date).prefix(1).uppercased()
    }
}

// MARK: - Quick Add Button

struct QuickAddButton: View {
    let amount: Int
    let icon: String
    @ObservedObject var viewModel: WaterViewModel
    
    var body: some View {
        Button {
            if amount == 0 {
                viewModel.handle(.showAddWaterDialog)
            } else {
                viewModel.handle(.addWater(amount))
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.waterGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                if amount > 0 {
                    Text("\(amount) мл")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                } else {
                    Text("Свое")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.waterGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
        }
    }
}

// MARK: - Water Entry Row

struct WaterEntryRow: View {
    let entry: WaterEntry
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "drop.fill")
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.waterGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.amount) мл")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(timeString(for: entry.timestamp))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
            }
            
            Spacer()
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.error)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Add Water Dialog

struct AddWaterDialog: View {
    @ObservedObject var viewModel: WaterViewModel
    @State private var customAmount: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                VStack(spacing: 24) {
                    Text("Добавить воду")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    // Предустановленные значения
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach([100, 150, 200, 250, 300, 350, 400, 500, 750], id: \.self) { amount in
                            Button {
                                viewModel.handle(.selectAmount(amount))
                                viewModel.handle(.addWater(amount))
                            } label: {
                                Text("\(amount) мл")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(
                                        viewModel.state.selectedAmount == amount
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(
                                                viewModel.state.selectedAmount == amount
                                                ? LinearGradient(
                                                    colors: AppColors.waterGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                                : LinearGradient(
                                                    colors: [Color.clear],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: AppColors.waterGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        ),
                                                        lineWidth: 1.5
                                                    )
                                            }
                                    }
                            }
                        }
                    }
                    
                    // Кастомное значение
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Или введите своё количество")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        
                        TextField("мл", text: $customAmount)
                            .keyboardType(.numberPad)
                            .focused($isFocused)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: AppColors.waterGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    }
                            }
                            .onSubmit {
                                if let amount = Int(customAmount), amount > 0 {
                                    viewModel.handle(.addWater(amount))
                                }
                            }
                    }
                    
                    Button {
                        if let amount = Int(customAmount), amount > 0 {
                            viewModel.handle(.addWater(amount))
                        }
                    } label: {
                        Text("Добавить")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: AppColors.waterGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                    }
                    .disabled(customAmount.isEmpty || Int(customAmount) == nil || Int(customAmount)! <= 0)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        viewModel.handle(.hideAddWaterDialog)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}

// MARK: - Water Settings View

struct WaterSettingsView: View {
    @ObservedObject var viewModel: WaterViewModel
    @State private var settings: WaterSettings
    
    init(viewModel: WaterViewModel) {
        self.viewModel = viewModel
        if let existing = viewModel.state.settings {
            _settings = State(initialValue: WaterSettings(
                gender: existing.gender,
                height: existing.height,
                weight: existing.weight,
                activityLevel: existing.activityLevel,
                targetAmount: existing.targetAmount,
                remindersEnabled: existing.remindersEnabled,
                reminderInterval: existing.reminderInterval
            ))
        } else {
            _settings = State(initialValue: WaterSettings())
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section("Персональные данные") {
                        Picker("Пол", selection: $settings.genderRaw) {
                            ForEach(Gender.allCases, id: \.rawValue) { gender in
                                Text(gender.displayName).tag(gender.rawValue)
                            }
                        }
                        
                        HStack {
                            Text("Рост")
                            Spacer()
                            TextField("см", value: $settings.height, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("см")
                        }
                        
                        HStack {
                            Text("Вес")
                            Spacer()
                            TextField("кг", value: $settings.weight, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("кг")
                        }
                        
                        Picker("Активность", selection: $settings.activityLevelRaw) {
                            ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                                Text(level.displayName).tag(level.rawValue)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    Section("Цель") {
                        HStack {
                            Text("Целевое количество")
                            Spacer()
                            TextField("мл", value: $settings.targetAmount, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text("мл")
                        }
                        
                        if settings.targetAmount == 0 {
                            Text("Автоматический расчет: \(settings.calculateRecommendedAmount()) мл")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        viewModel.handle(.hideSettings)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        viewModel.handle(.updateSettings(settings))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WaterView()
    }
    .modelContainer(for: [WaterEntry.self, WaterSettings.self])
}
