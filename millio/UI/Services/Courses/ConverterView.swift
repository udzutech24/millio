import SwiftUI
import Foundation
#if os(iOS)
import UIKit
import AudioToolbox
#endif

struct ConverterView: View {
    @StateObject private var viewModel = ConverterViewModel()
    @State private var deleteButtonTapCount = 0
    
    private var decSep: String { Locale.current.decimalSeparator ?? "," }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    
    
    // MARK: - Sounds
    
#if os(iOS)
    private func playKeyTapSound() {
        AudioServicesPlaySystemSound(1104) // Tink sound
    }
    
    private func playDeleteSound() {
        AudioServicesPlaySystemSound(1155) // iOS Calculator delete sound
    }
#else
    private func playKeyTapSound() {}
    private func playDeleteSound() {}
#endif
    
    
    // MARK: - Compile-friendly layout
    
    private struct Layout {
        let totalH: CGFloat
        let bottomSafe: CGFloat
        let headerH: CGFloat
        let keySpacing: CGFloat
        let desiredRows: Int
        let rowSpacing: CGFloat
        let rowH: CGFloat
        let keyH: CGFloat
        let fontSize: CGFloat
    }
    
    
    private func makeLayout(totalH: CGFloat) -> Layout {
#if os(iOS)
        let bottomSafe = converterSafeAreaBottom()
#else
        let bottomSafe: CGFloat = 0
#endif
        let headerH: CGFloat = 52
        
        let keySpacing: CGFloat = totalH < 700 ? 10 : 12
        let desiredRows: Int = 6
        let rowSpacing: CGFloat = 8
        
        let keypadVerticalInsets = keySpacing * 4 + bottomSafe + 4
        let reservedKeypad = 5 * 56 + keypadVerticalInsets
        
        let rowH = adaptiveRowHeight(
            totalH: totalH,
            reservedKeypad: CGFloat(reservedKeypad),
            desiredRows: desiredRows,
            rowSpacing: rowSpacing
        )
        
        let listBlockH = CGFloat(desiredRows) * rowH + CGFloat(desiredRows - 1) * rowSpacing + 8 + 8
        let availableForKeypad = max(260, totalH - headerH - 8 - listBlockH)
        let keyH = max(52, floor((availableForKeypad - keypadVerticalInsets) / 5))
        let fontSize: CGFloat = keyH >= 60 ? 22 : (keyH >= 54 ? 20 : 18)
        
        return Layout(
            totalH: totalH,
            bottomSafe: bottomSafe,
            headerH: headerH,
            keySpacing: keySpacing,
            desiredRows: desiredRows,
            rowSpacing: rowSpacing,
            rowH: rowH,
            keyH: keyH,
            fontSize: fontSize
        )
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            GeometryReader { geo in
                let layout = makeLayout(totalH: geo.size.height)
                mainContent(layout: layout)
            }
        }
        .task {
            if viewModel.state.allRates.count <= 1 {
                await viewModel.fetchRates()
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showPicker },
            set: { if !$0 { viewModel.handle(.hidePicker) } }
        )) {
            pickerSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showSettingsSheet },
            set: { if !$0 { viewModel.handle(.hideSettingsSheet) } }
        )) {
            settingsSheet
        }
        .confirmationDialog("Знаки после запятой", isPresented: Binding(
            get: { viewModel.state.showFractionDialog },
            set: { if !$0 { viewModel.handle(.hideFractionDialog) } }
        ), titleVisibility: .visible) {
            ForEach(0...8, id: \.self) { n in
                Button(n == viewModel.currentFractionDigits ? "\(n) ✓" : "\(n)") {
                    viewModel.handle(.setFractionDigits(n))
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showShareSheet },
            set: { viewModel.state.showShareSheet = $0 }
        )) {
            if let img = viewModel.state.shareImage {
#if os(iOS)
                ActivityView(activityItems: [ImageItem(image: img, compressionQuality: 0.92)])
                    .ignoresSafeArea()
#endif
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { topToolbar }
    }
    
    // MARK: - Split view helpers
    
    @ViewBuilder
    private func mainContent(layout: Layout) -> some View {
        VStack(spacing: 8) {
            currencyList(layout: layout)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            Spacer(minLength: 8)
            
            VStack(spacing: 0) {
                keypad(height: layout.keyH, spacing: layout.keySpacing, fontSize: layout.fontSize)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, max(4, layout.bottomSafe))
            }
            .background(Color.clear)
        }
    }
    
    @ViewBuilder
    private func currencyList(layout: Layout) -> some View {
        VStack(spacing: layout.rowSpacing) {
            ForEach(Array(viewModel.state.selectedCurrencies.enumerated()), id: \.offset) { idx, code in
                let isActive = (viewModel.state.activeCode == code)
                let effectiveRowH = isActive ? layout.rowH * 1.20 : layout.rowH
                currencyRow(index: idx,
                            code: code,
                            valueText: viewModel.displayValue(for: code),
                            isActive: isActive,
                            rowHeight: effectiveRowH)
            }
            let placeholders = max(0, layout.desiredRows - viewModel.state.selectedCurrencies.count)
            ForEach(0..<placeholders, id: \.self) { _ in
                placeholderRow(rowHeight: layout.rowH)
                    .onTapGesture {
                        viewModel.handle(.addCurrency)
                    }
            }
        }
    }
    
    private var pickerSheet: some View {
        NavigationStack {
            CurrencyPickerView(
                allCodes: viewModel.allAvailableCodes,
                searchText: Binding(
                    get: { viewModel.state.searchText },
                    set: { viewModel.handle(.updateSearchText($0)) }
                ),
                selectedCodes: viewModel.state.selectedCurrencies,
                onSelect: { code in
                    viewModel.handle(.applyPickerSelection(code))
                }
            )
            .navigationTitle(viewModel.state.replaceIndex == nil ? "Добавить валюту" : "Заменить валюту")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        viewModel.handle(.hidePicker)
                    }
                }
            }
        }
    }
    
    
    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Курс") {
                    DisclosureGroup {
                        ForEach(RateSource.allCases) { src in
                            Button {
                                viewModel.handle(.setRateSource(src))
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(src.title)
                                        Text(src.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                    Spacer()
                                    if src == viewModel.state.rateSource {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppColors.coursesGradient.first!)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Источник курса")
                            Spacer()
                            Text(viewModel.state.rateSource.title)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    
                    Toggle("Показывать индикатор без интернета", isOn: Binding(
                        get: { viewModel.state.showOfflineBadge },
                        set: { viewModel.handle(.setShowOfflineBadge($0)) }
                    ))
                    
                    HStack {
                        Text("Последнее обновление")
                        Spacer()
                        Text(viewModel.lastUpdatedText)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    
                    Button {
                        viewModel.handle(.refreshRates(force: true))
                    } label: {
                        Label("Обновить курсы", systemImage: "arrow.clockwise")
                    }
                }
                
                Section("Точность") {
                    Picker("Знаков после запятой", selection: Binding(
                        get: { viewModel.state.fractionDigits },
                        set: { viewModel.handle(.setFractionDigits($0)) }
                    )) {
                        ForEach(0...8, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Ощущения") {
                    Toggle("Тактильный отклик", isOn: Binding(
                        get: { viewModel.state.hapticsEnabled },
                        set: { viewModel.handle(.setHapticsEnabled($0)) }
                    ))
                }
                
                Section("Виджет") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Виджет можно добавить как отдельный target (WidgetKit) и читать настройки конвертора через App Group / UserDefaults.")
                            .font(.footnote)
                            .foregroundStyle(AppColors.textTertiary)
                        Text("Если хочешь — я дам готовый WidgetKit target под твой дизайн.")
                            .font(.footnote)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Конвертор")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") {
                        viewModel.handle(.hideSettingsSheet)
                    }
                }
            }
        }
    }
    
    
    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
            }
            .accessibilityLabel("Назад")
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                
                if let iconName = viewModel.connectivityIconName {
                    Image(systemName: iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(iconName == "wifi.slash" ? AppColors.error.opacity(0.9) : AppColors.textTertiary)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Состояние курсов")
                }
                
                Button {
                    guard viewModel.canRemoveCurrency else { return }
                    viewModel.handle(.removeLastCurrency)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3.weight(.semibold))
                        .opacity(viewModel.canRemoveCurrency ? 1.0 : 0.35)
                        .frame(width: 28, height: 28)
                }
                .disabled(!viewModel.canRemoveCurrency)
                .accessibilityLabel("Убрать валюту")
                
                Button {
                    guard viewModel.canAddCurrency else { return }
                    viewModel.handle(.addCurrency)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3.weight(.semibold))
                        .opacity(viewModel.canAddCurrency ? 1.0 : 0.35)
                        .frame(width: 28, height: 28)
                }
                .disabled(!viewModel.canAddCurrency)
                .accessibilityLabel("Добавить валюту")
                
                Button {
                    handleShareTap()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                }
                .accessibilityLabel("Поделиться")
                
                Button {
                    viewModel.handle(.showSettingsSheet)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Настройки точности")
            }
        }
    }
    
    
    // MARK: - Currency row
    private func currencyRow(index: Int, code: String, valueText: String, isActive: Bool, rowHeight: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.handle(.replaceCurrency(index))
            } label: {
                Text(viewModel.flagEmoji(for: code))
                    .font(.system(size: 20))
                    .frame(width: 40, height: rowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    viewModel.handle(.selectCurrency(code))
                }
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(code)
                                .font(isActive ? .title3.weight(.semibold) : .headline.weight(.semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        if isActive {
                            Button {
                                viewModel.handle(.toggleCalcMode)
                            } label: {
                                Image(systemName: viewModel.state.calcModeOn ? "circle.grid.3x3.fill" : "circle.grid.3x3")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(viewModel.state.calcModeOn ? AppColors.textPrimary : AppColors.textTertiary)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        Circle().fill(viewModel.state.calcModeOn ? AppColors.coursesGradient.first!.opacity(0.85) : AppColors.iconBackground)
                                    )
                                    .overlay(
                                        Circle().strokeBorder(AppColors.textPrimary.opacity(viewModel.state.calcModeOn ? 0.0 : 0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Калькулятор")
                        }
                    }
                    Spacer()
                    if isActive && viewModel.state.calcModeOn {
                        VStack(alignment: .trailing, spacing: 2) {
                            // Строка выражения: 100-2+3 или 100-2+3=101
                            if !viewModel.state.expressionText.isEmpty {
                                Text(viewModel.state.expressionText)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            HStack(spacing: 6) {
                                TextField("0", text: Binding(
                                    get: { viewModel.state.inputText },
                                    set: { viewModel.handle(.updateInputText($0)) }
                                ))
                                .keyboardType(.decimalPad)
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(.done)
                                .frame(minWidth: 80)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(AppColors.textPrimary.opacity(0.1))
                            )
                        }
                    } else {
                        Text(valueText)
                            .font(isActive ? .title2.weight(.bold) : .title3.weight(.semibold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Group {
                        if isActive {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: AppColors.coursesGradient, startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 1.5
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
                        }
                    }
                )
                .shadow(color: .black.opacity(isActive ? 0.22 : 0.10), radius: isActive ? 9 : 5, x: 0, y: isActive ? 6 : 3)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
#if os(iOS)
                    UIPasteboard.general.string = viewModel.displayValue(for: code) + " " + code
#endif
                } label: { Label("Копировать значение", systemImage: "doc.on.doc") }
                Button(role: .destructive) {
                    viewModel.handle(.removeCurrency(index))
                } label: { Label("Удалить", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.handle(.removeCurrency(index))
            } label: { Label("Удалить", systemImage: "trash") }
        }
    }
    
    private func placeholderRow(rowHeight: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 40, height: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            HStack {
                Text("Добавить валюту")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
            )
        }
        .contentShape(Rectangle())
    }
    
    
    // MARK: - Keypad (нижний ряд заполняет ширину)
    private enum KeyKind { case dark, gray, accent }
    
    @ViewBuilder
    private func neonCapsule(background: Color, corner: CGFloat = 28) -> some View {
        Capsule(style: .continuous)
            .fill(background)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: AppColors.coursesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.0
                    )
            )
    }
    
    private struct NeonPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: configuration.isPressed)
        }
    }
    
    private func keypad(height: CGFloat, spacing: CGFloat, fontSize: CGFloat) -> some View {
        VStack(spacing: spacing) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 4), spacing: spacing) {
                // Row 1
                key("C", kind: .gray, height: height, fontSize: fontSize) { viewModel.handle(.clearAll) }
                iconKey("delete.left", kind: .gray, height: height, fontSize: fontSize) { viewModel.handle(.backspace) }
                key("%", kind: .gray, height: height, fontSize: fontSize) { viewModel.handle(.percent) }
                iconKey("divide", kind: .accent, height: height, fontSize: fontSize) { viewModel.handle(.operation("/")) }
                
                // Row 2
                key("7", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("7")) }
                key("8", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("8")) }
                key("9", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("9")) }
                iconKey("multiply", kind: .accent, height: height, fontSize: fontSize) { viewModel.handle(.operation("*")) }
                
                // Row 3
                key("4", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("4")) }
                key("5", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("5")) }
                key("6", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("6")) }
                iconKey("minus", kind: .accent, height: height, fontSize: fontSize) { viewModel.handle(.operation("-")) }
                
                // Row 4
                key("1", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("1")) }
                key("2", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("2")) }
                key("3", height: height, fontSize: fontSize) { viewModel.handle(.appendDigit("3")) }
                iconKey("plus", kind: .accent, height: height, fontSize: fontSize) { viewModel.handle(.operation("+")) }
            }
            
            // Row 5 — заполняет ширину
            HStack(spacing: spacing) {
                key("0", height: height, fontSize: fontSize) { viewModel.handle(.appendZero) }
                    .frame(maxWidth: .infinity)
                key(decSep, height: height, fontSize: fontSize) { viewModel.handle(.appendComma) }
                    .frame(maxWidth: .infinity)
                key("=", kind: .accent, height: height, fontSize: fontSize) { viewModel.handle(.equal) }
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func iconKey(_ system: String, kind: KeyKind = .accent, height: CGFloat, fontSize: CGFloat, action: @escaping () -> Void) -> some View {
        let isDelete = system == "delete.left"
        Button {
#if os(iOS)
            if isDelete {
                playDeleteSound()
                deleteButtonTapCount += 1
            } else {
                playKeyTapSound()
            }
#endif
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: fontSize, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    neonCapsule(background: backgroundColor(for: kind))
                )
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .buttonStyle(NeonPressStyle())
    }
    
    @ViewBuilder
    private func key(_ title: String, kind: KeyKind = .dark, height: CGFloat, fontSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
#if os(iOS)
            playKeyTapSound()
#endif
            action()
        } label: {
            Text(title)
                .font(.system(size: title == "=" ? fontSize+1 : fontSize, weight: title == "=" ? .bold : .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    neonCapsule(background: backgroundColor(for: kind))
                )
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .buttonStyle(NeonPressStyle())
    }
    
    private func backgroundColor(for kind: KeyKind) -> Color {
        switch kind {
        case .dark: return Color.black.opacity(0.3)
        case .gray: return AppColors.iconBackground
        case .accent: return Color.black.opacity(0.4)
        }
    }
    
    private func adaptiveRowHeight(totalH: CGFloat, reservedKeypad: CGFloat, desiredRows: Int, rowSpacing: CGFloat) -> CGFloat {
        let availableForRows = max(280, totalH - reservedKeypad)
        let h = floor((availableForRows - CGFloat(desiredRows - 1) * rowSpacing) / CGFloat(desiredRows))
        return min(max(h, 58), 80)
    }
    
    // MARK: - Share
    
    private func handleShareTap() {
        #if os(iOS)
        let shareData = viewModel.getShareData()
        let size = CGSize(width: 1080, height: 900)
        let card = ShareCardView(
            dateString: shareData.dateString,
            rows: shareData.rows,
            highlightedCode: shareData.highlightedCode
        )
        .frame(width: size.width, height: size.height)
        
        if let img = ShareRenderer.render(card: card, size: size, scale: 4) {
            viewModel.setShareImage(img)
            viewModel.handle(.prepareShare)
        }
        #endif
    }
    
#if os(iOS)
    private func converterSafeAreaBottom() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window.safeAreaInsets.bottom
            }
        }
        return scenes.first?.windows.first?.safeAreaInsets.bottom ?? 0
    }
#endif

}

#if DEBUG
struct ConverterView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ConverterView()
                .navigationTitle("")
        }
    }
}
#endif

