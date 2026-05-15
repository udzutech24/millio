import SwiftUI

// MARK: - Account Icon Picker Sheet

struct AccountIconPickerSheet: View {
    @Binding var iconName: String?
    @Binding var iconColor: String?

    @Environment(\.dismiss) private var dismiss

    @State private var mode: PickerMode = .presets
    @State private var monogramDraft: String = ""
    @State private var selectedColorHex: String? = nil
    @State private var customColor: Color = .blue

    private enum PickerMode: String, CaseIterable {
        case presets  = "account.icon_picker.tab.presets"
        case monogram = "account.icon_picker.tab.monogram"
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

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
                        }
                        colorSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear(perform: syncStateFromBindings)
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
            ForEach(PickerMode.allCases, id: \.self) { m in
                Text(LocalizedStringKey(m.rawValue)).tag(m)
            }
        }
        .pickerStyle(.segmented)
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
        if let name = iconName, AccountIconSet.isMonogram(name) {
            mode = .monogram
            monogramDraft = AccountIconSet.monogramText(name)
        }
    }

    private func applyAndDismiss() {
        switch mode {
        case .presets:
            break // iconName уже обновляется по тапу
        case .monogram:
            let text = AccountIconSet.normalizedMonogram(monogramDraft)
            iconName = text.isEmpty ? nil : AccountIconSet.monogramIconName(text)
        }
        iconColor = selectedColorHex
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
