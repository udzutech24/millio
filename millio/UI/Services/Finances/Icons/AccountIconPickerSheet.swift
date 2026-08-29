import SwiftUI

// MARK: - Account Icon Picker Sheet

struct AccountIconPickerSheet: View {
    @Binding var iconName: String?
    @Binding var iconColor: String?
    /// nil = вкладки «Дизайн» в этом контексте нет. Так работают иконка группы и форма создания
    /// счёта: у них нет строки `AccountAppearance`, куда можно записать выбранный пресет.
    var presetRaw: Binding<String?>?

    @Environment(\.dismiss) private var dismiss
    // Опциональные, потому что лист открывается в том числе из превью и из контекстов без роутера:
    // обращение к отсутствующему `@Environment(Observable)` — это краш, а не пустое значение.
    @Environment(AppState.self) private var appState: AppState?
    @Environment(AppRouter.self) private var router: AppRouter?

    @State private var mode: PickerMode = .presets
    @State private var monogramDraft: String = ""
    @State private var selectedColorHex: String? = nil
    @State private var selectedPresetRaw: String? = nil
    @State private var customColor: Color = .blue
    @State private var showGalleryProAlert = false

    private enum PickerMode: String, CaseIterable {
        case presets  = "account.icon_picker.tab.presets"
        case monogram = "account.icon_picker.tab.monogram"
        case design   = "account.icon_picker.tab.design"
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
    private let designColumns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.m), count: 3)

    private var availableModes: [PickerMode] {
        presetRaw == nil ? [.presets, .monogram] : PickerMode.allCases
    }

    private var canUseGallery: Bool {
        EntitlementPolicy.canUseAccountAppearanceGallery(isPro: appState?.isPro ?? false)
    }

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 0) {
                header
                modePicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 20) {
                        switch mode {
                        case .presets: presetsSection
                        case .monogram: monogramSection
                        case .design: designSection
                        }
                        // В галерее своя палитра: отдельный выбор цвета рядом с ней означал бы
                        // два конкурирующих источника акцента на одном экране.
                        if mode != .design { colorSection }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear(perform: syncStateFromBindings)
        .premiumUpsellAlert(
            isPresented: $showGalleryProAlert,
            titleKey: "account.appearance.gallery.pro_title",
            messageKey: "account.appearance.gallery.pro_message",
            onSubscribe: {
                // Экран подписки живёт в основном стеке — лист сначала закрываем, иначе push
                // произойдёт под ним и пользователь его не увидит.
                dismiss()
                router?.push(.subscription)
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(String(localized: "common.cancel")) { dismiss() }
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text("account.icon_picker.title", tableName: "Localizable")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button(String(localized: "common.done")) { applyAndDismiss() }
                .foregroundStyle(AppColors.financesGradient.first ?? .blue)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Mode picker (segmented)

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(availableModes, id: \.self) { m in
                Text(LocalizedStringKey(m.rawValue)).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Дизайны (галерея пресетов, PRO)

    private var designSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            if !canUseGallery { galleryLockNotice }

            LazyVGrid(columns: designColumns, spacing: AppSpacing.m) {
                designResetCell
                ForEach(AccountAppearancePreset.allCases) { preset in
                    designCell(preset)
                }
            }
            // Free видит саму галерею (что именно он получит по подписке), но выбор не применяется:
            // тап ведёт на paywall. Пустой замок вместо витрины конвертирует хуже.
            .opacity(canUseGallery ? 1 : 0.6)
        }
    }

    private var galleryLockNotice: some View {
        Button {
            showGalleryProAlert = true
        } label: {
            Label(L("account.appearance.gallery.locked"), systemImage: "lock.fill")
                .font(.millioCalloutSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                        .fill(AppColors.iconBackground)
                )
        }
        .buttonStyle(.plain)
    }

    private func designCell(_ preset: AccountAppearancePreset) -> some View {
        let isSelected = selectedPresetRaw == preset.rawValue
        return Button {
            selectPreset(preset.rawValue)
        } label: {
            VStack(spacing: AppSpacing.xs) {
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: preset.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 56)
                    .overlay { if isSelected { designSelectionRing } }

                Text(LocalizedStringKey(preset.titleKey))
                    .font(.millioCaption2Medium)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    /// «Без дизайна» — возврат к вычисляемому дефолту оформления (`AccountAppearanceDefaults`).
    private var designResetCell: some View {
        let isSelected = selectedPresetRaw == nil
        return Button {
            selectPreset(nil)
        } label: {
            VStack(spacing: AppSpacing.xs) {
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .fill(AppColors.iconBackground)
                    .frame(height: 56)
                    .overlay {
                        Image(systemName: "slash.circle")
                            .font(.millioHeadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .overlay { if isSelected { designSelectionRing } }

                Text(L("account.appearance.preset.none"))
                    .font(.millioCaption2Medium)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var designSelectionRing: some View {
        RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
    }

    private func selectPreset(_ raw: String?) {
        guard canUseGallery else {
            showGalleryProAlert = true
            return
        }
        selectedPresetRaw = raw
        // Дизайн и ручной цвет — взаимоисключающие источники акцента: иначе строка списка красилась
        // бы старым цветом, а hero — новым градиентом, и «дизайн не применился» на глаз.
        if raw != nil {
            selectedColorHex = nil
            iconColor = nil
        }
    }

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(AccountIconSet.categories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(category.titleKey))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(category.icons, id: \.self) { symbol in
                            presetCell(symbol: symbol)
                        }
                    }
                }
            }
        }
    }

    private func presetCell(symbol: String) -> some View {
        let isSelected = iconName == symbol
        return Button {
            iconName = symbol
        } label: {
            AccountIconBadgeView(
                iconName: symbol,
                iconColor: selectedColorHex,
                fallback: symbol,
                size: 48
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: AppColors.financesGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monogram

    private var monogramSection: some View {
        VStack(spacing: 16) {
            AccountIconBadgeView(
                iconName: monogramDraft.isEmpty ? nil : AccountIconSet.monogramIconName(monogramDraft),
                iconColor: selectedColorHex,
                fallback: "person.fill",
                size: 72
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("account.icon_picker.monogram.label"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)

                TextField(
                    String(localized: "account.icon_picker.monogram.placeholder"),
                    text: $monogramDraft
                )
                .onChange(of: monogramDraft) { _, new in
                    if new.count > 3 { monogramDraft = String(new.prefix(3)) }
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Color section (shared)

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("account.icon_picker.color.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                // Дефолт (градиент)
                defaultColorCell

                ForEach(AccountIconSet.palette) { entry in
                    colorCell(hex: entry.hex)
                }
            }

            // Color wheel
            HStack {
                Text(LocalizedStringKey("account.icon_picker.color.custom"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: customColor) { _, new in
                        selectedColorHex = new.hexString
                        iconColor = selectedColorHex
                        selectedPresetRaw = nil
                    }
            }
            .padding(.top, 4)
        }
    }

    private var defaultColorCell: some View {
        let isSelected = selectedColorHex == nil
        return Button {
            selectedColorHex = nil
            iconColor = nil
            selectedPresetRaw = nil
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: AppColors.financesGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 36)
                .overlay {
                    if isSelected { selectionRing }
                }
        }
        .buttonStyle(.plain)
    }

    private func colorCell(hex: String) -> some View {
        let isSelected = selectedColorHex == hex
        return Button {
            selectedColorHex = hex
            iconColor = hex
            // Ручной цвет отменяет дизайн — обратная сторона правила из `selectPreset`.
            selectedPresetRaw = nil
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: hex))
                .frame(height: 36)
                .overlay { if isSelected { selectionRing } }
        }
        .buttonStyle(.plain)
    }

    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            .padding(1)
    }

    // MARK: - Logic

    private func syncStateFromBindings() {
        selectedColorHex = iconColor
        selectedPresetRaw = presetRaw?.wrappedValue
        if let name = iconName, AccountIconSet.isMonogram(name) {
            mode = .monogram
            monogramDraft = AccountIconSet.monogramText(name)
        }
    }

    private func applyAndDismiss() {
        switch mode {
        case .presets, .design:
            break // iconName / выбранный дизайн уже обновлены по тапу
        case .monogram:
            let text = AccountIconSet.normalizedMonogram(monogramDraft)
            iconName = text.isEmpty ? nil : AccountIconSet.monogramIconName(text)
        }
        iconColor = selectedColorHex
        presetRaw?.wrappedValue = selectedPresetRaw
        dismiss()
    }
}

// MARK: - Color hex helper

private extension Color {
    var hexString: String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#Preview {
    @Previewable @State var icon: String? = nil
    @Previewable @State var color: String? = nil
    AccountIconPickerSheet(iconName: $icon, iconColor: $color)
}
