import SwiftUI
import Foundation
#if os(iOS)
import UIKit
import AudioToolbox
#endif

struct ConverterView: View {
    @StateObject private var viewModel = ConverterViewModel()
    @State private var deleteButtonTapCount = 0
    @State private var isRateSourceExpanded = false
    
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
        let topPadding: CGFloat = 4
        
        // Фиксированная высота кнопок клавиатуры по дизайну
        let minKeyHeight: CGFloat = 64
        let minKeySpacing: CGFloat = 4
        let keypadRows: Int = 5
        
        // Вычисляем минимальную высоту клавиатуры (без лишних отступов)
        let minKeypadHeight = CGFloat(keypadRows) * minKeyHeight + CGFloat(keypadRows - 1) * minKeySpacing + bottomSafe
        
        // Доступная высота для контента (исключая header и клавиатуру)
        let availableForContent = max(0, totalH - headerH - minKeypadHeight - topPadding)
        
        // Адаптируем размеры клавиатуры под доступное место
        let keypadAvailableHeight = max(minKeypadHeight, totalH - headerH - availableForContent - topPadding)
        
        // Вычисляем размеры кнопок и отступы с учетом доступного места
        let keypadContentHeight = max(0, keypadAvailableHeight - bottomSafe)
        let keyH = minKeyHeight
        
        // Адаптируем spacing между кнопками
        let actualKeypadContentHeight = CGFloat(keypadRows) * keyH
        let remainingSpace = max(0, keypadContentHeight - actualKeypadContentHeight)
        let keySpacing = min(5, minKeySpacing + (remainingSpace > 0 ? floor(remainingSpace / CGFloat(keypadRows - 1)) : 0))
        
        // Для фиксированной высоты 64 используем фиксированный размер шрифта
        let fontSize: CGFloat = 22
        
        // Для списка валют используем адаптивную высоту строк
        let desiredRows: Int = 6
        let rowSpacing: CGFloat = 8
        let minRowHeight: CGFloat = 58
        let maxRowHeight: CGFloat = 80
        
        // Вычисляем высоту строки списка валют (гарантируем, что все 6 ячеек влезут)
        let listAvailableHeight = max(0, availableForContent - topPadding)
        let calculatedRowH = (listAvailableHeight - CGFloat(desiredRows - 1) * rowSpacing) / CGFloat(desiredRows)
        let rowH = min(maxRowHeight, max(minRowHeight, floor(max(0, calculatedRowH))))
        
        // Гарантируем, что все значения конечные и положительные
        let safeKeyH = keyH.isFinite && keyH > 0 ? keyH : minKeyHeight
        let safeKeySpacing = keySpacing.isFinite && keySpacing >= 0 ? keySpacing : minKeySpacing
        let safeRowH = rowH.isFinite && rowH > 0 ? rowH : minRowHeight
        let safeRowSpacing = rowSpacing.isFinite && rowSpacing >= 0 ? rowSpacing : 8
        let safeFontSize = fontSize.isFinite && fontSize > 0 ? fontSize : 18
        
        return Layout(
            totalH: totalH,
            bottomSafe: bottomSafe,
            headerH: headerH,
            keySpacing: safeKeySpacing,
            desiredRows: desiredRows,
            rowSpacing: safeRowSpacing,
            rowH: safeRowH,
            keyH: safeKeyH,
            fontSize: safeFontSize
        )
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            GeometryReader { geo in
                let layout = makeLayout(totalH: geo.size.height)
                mainContent(layout: layout)
            }
            
            // Toast для ошибок
            VStack {
                Spacer()
                if let message = viewModel.state.toastMessage {
                    ToastView(message: message, isPresented: Binding(
                        get: { viewModel.state.showToast },
                        set: { viewModel.state.showToast = $0 }
                    ))
                }
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
            set: { 
                if !$0 {
                    viewModel.state.showShareSheet = false
                    viewModel.state.shareImage = nil
                }
            }
        )) {
#if os(iOS)
            if let img = viewModel.state.shareImage {
                ActivityView(activityItems: [ImageItem(image: img, compressionQuality: 0.92)])
                    .ignoresSafeArea()
            }
#endif
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { topToolbar }
    }
    
    // MARK: - Split view helpers
    
    @ViewBuilder
    private func mainContent(layout: Layout) -> some View {
        VStack(spacing: 0) {
            currencyList(layout: layout)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)

            Spacer(minLength: 0)

            calculatorPanel
                .padding(.horizontal, 16)
                .padding(.top, 4)
            
            // Клавиатура всегда внизу
            VStack(spacing: 0) {
                keypad(height: layout.keyH, spacing: layout.keySpacing, fontSize: layout.fontSize)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, layout.bottomSafe) // Минимальный отступ только для safe area
            }
            .background(Color.clear)
        }
    }
    
    @ViewBuilder
    private func currencyList(layout: Layout) -> some View {
        let safeRowSpacing = layout.rowSpacing.isFinite && layout.rowSpacing >= 0 ? layout.rowSpacing : 8
        let regularRowHeight: CGFloat = 40
        let activeRowHeight: CGFloat = 46
        
        VStack(spacing: safeRowSpacing) {
            ForEach(Array(viewModel.state.selectedCurrencies.enumerated()), id: \.offset) { idx, code in
                let isActive = (viewModel.state.activeCode == code)
                let finalRowH = isActive ? activeRowHeight : regularRowHeight
                currencyRow(index: idx,
                            code: code,
                            valueText: viewModel.displayValue(for: code),
                            isActive: isActive,
                            rowHeight: finalRowH)
            }
            let placeholders = max(0, layout.desiredRows - viewModel.state.selectedCurrencies.count)
            ForEach(0..<placeholders, id: \.self) { _ in
                placeholderRow(rowHeight: regularRowHeight)
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
            .interactiveDismissDisabled(false)
        }
    }
    
    
    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            FinancesSectionHeader(title: "Курс")
                            FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? AppColors.brandPrimary) {
                                VStack(spacing: 0) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isRateSourceExpanded.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text("Источник курса")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(AppColors.textPrimary)
                                            Spacer()
                                            Text(viewModel.state.rateSource.title)
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundStyle(AppColors.textTertiary)
                                            Image(systemName: isRateSourceExpanded ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)

                                    if isRateSourceExpanded {
                                        FinancesRowDivider(leadingPadding: 16)
                                        VStack(spacing: 0) {
                                            ForEach(Array(RateSource.allCases.enumerated()), id: \.element.id) { index, src in
                                                Button {
                                                    viewModel.handle(.setRateSource(src))
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        isRateSourceExpanded = false
                                                    }
                                                } label: {
                                                    HStack(spacing: 12) {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(src.title)
                                                                .font(.system(size: 15, weight: .medium))
                                                                .foregroundStyle(AppColors.textPrimary)
                                                            Text(src.subtitle)
                                                                .font(.system(size: 12, weight: .regular))
                                                                .foregroundStyle(AppColors.textTertiary)
                                                                .multilineTextAlignment(.leading)
                                                        }
                                                        Spacer()
                                                        if src == viewModel.state.rateSource {
                                                            Image(systemName: "checkmark")
                                                                .font(.system(size: 13, weight: .semibold))
                                                                .foregroundStyle(
                                                                    LinearGradient(
                                                                        colors: AppColors.financesGradient,
                                                                        startPoint: .leading,
                                                                        endPoint: .trailing
                                                                    )
                                                                )
                                                        }
                                                    }
                                                    .padding(.vertical, 12)
                                                    .padding(.horizontal, 16)
                                                }
                                                .buttonStyle(.plain)

                                                if index < RateSource.allCases.count - 1 {
                                                    FinancesRowDivider(leadingPadding: 16)
                                                }
                                            }
                                        }
                                    }

                                    FinancesRowDivider(leadingPadding: 16)

                                    HStack(spacing: 12) {
                                        Text("Последнее обновление")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        Text(viewModel.lastUpdatedText)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)

                                    FinancesRowDivider(leadingPadding: 16)

                                    Button {
                                        #if os(iOS)
                                        if viewModel.state.hapticsEnabled {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                        #endif
                                        viewModel.handle(.refreshRates(force: true))
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "arrow.clockwise")
                                            Text(viewModel.state.isFetchingRates ? "Обновляем..." : "Обновить курсы")
                                        }
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.financesGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(viewModel.state.isFetchingRates)
                                    .opacity(viewModel.state.isFetchingRates ? 0.5 : 1.0)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            FinancesSectionHeader(title: "Точность")
                            FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? AppColors.brandPrimary, contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Знаков после запятой")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
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
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            FinancesSectionHeader(title: "Ощущения")
                            FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? AppColors.brandPrimary, contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                                Toggle("Тактильный отклик", isOn: Binding(
                                    get: { viewModel.state.hapticsEnabled },
                                    set: { viewModel.handle(.setHapticsEnabled($0)) }
                                ))
                                .tint(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                                .foregroundStyle(AppColors.textPrimary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Конвертор")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") {
                        viewModel.handle(.hideSettingsSheet)
                    }
                    .foregroundStyle(AppColors.textPrimary)
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
    
    private var calculatorPanel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(viewModel.state.expressionText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 8)
            Text(viewModel.state.inputText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func courseRowBackground(isActive: Bool) -> LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [Color(hex: "F7933A"), Color(hex: "F58A37")],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [Color(hex: "2F3035"), Color(hex: "25262A")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private func codePillBackground(isActive: Bool) -> Color {
        isActive ? Color(hex: "E9B183") : Color(hex: "5A5C61")
    }
    
    private func flagCircleBackground(isActive: Bool) -> some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "F79B41"), Color(hex: "F58A37")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color(hex: "34353A"), Color(hex: "26272B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func currencyFlagIcon(for code: String, size: CGFloat, isActive: Bool) -> some View {
        if let assetName = CurrencyFlags.assetName(for: code) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image("flag")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 24, height: 24)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(flagCircleBackground(isActive: isActive))
                )
        }
    }
    
    
    // MARK: - Currency row
    private func currencyRow(index: Int, code: String, valueText: String, isActive: Bool, rowHeight: CGFloat) -> some View {
        let safeRowHeight = rowHeight.isFinite && rowHeight > 0 ? rowHeight : 58
        
        return HStack(spacing: 10) {
            Button {
                viewModel.handle(.replaceCurrency(index))
            } label: {
                currencyFlagIcon(for: code, size: safeRowHeight, isActive: isActive)
            }
            .buttonStyle(.plain)
            
            Button {
                #if os(iOS)
                if viewModel.state.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    viewModel.handle(.selectCurrency(code))
                }
            } label: {
                HStack(spacing: 14) {
                    let codePillHeight: CGFloat = isActive ? 34 : 30
                    Text(code)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white)
                        .frame(width: 86, height: codePillHeight)
                        .background(
                            Capsule(style: .continuous)
                                .fill(codePillBackground(isActive: isActive))
                        )
                    Spacer()
                    Text(valueText)
                        .font(isActive ? .system(size: 17, weight: .bold) : .system(size: 15, weight: .regular))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Color.white)
                        .padding(.trailing, 2)
                }
                .padding(.leading, isActive ? 12 : 8)
                .padding(.trailing, 12)
                .frame(height: safeRowHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(courseRowBackground(isActive: isActive))
                )
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
        let safeRowHeight = rowHeight.isFinite && rowHeight > 0 ? rowHeight : 58
        
        return HStack(spacing: 10) {
            Image("flag")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 24, height: 24)
                .frame(width: safeRowHeight, height: safeRowHeight)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "34353A"), Color(hex: "26272B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            HStack {
                Spacer()
                Text("Добавить валюту")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(height: safeRowHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "2F3035"), Color(hex: "25262A")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .contentShape(Rectangle())
    }
    
    
    // MARK: - Keypad (нижний ряд заполняет ширину)
    private enum KeyKind { case dark, gray, grayTop, accent }
    
    @ViewBuilder
    private func neonCapsule(background: Color, corner: CGFloat = 28) -> some View {
        Capsule(style: .continuous)
            .fill(background)
    }
    
    private struct NeonPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: configuration.isPressed)
        }
    }
    
    private func keypad(height: CGFloat, spacing: CGFloat, fontSize: CGFloat) -> some View {
        GeometryReader { geometry in
            // Гарантируем валидные значения
            let safeHeight = height.isFinite && height > 0 ? height : 44
            let safeSpacing = spacing.isFinite && spacing >= 0 ? spacing : 6
            let safeFontSize = fontSize.isFinite && fontSize > 0 ? fontSize : 18
            let safeWidth = max(0, geometry.size.width - safeSpacing * 3)
            let buttonWidth = max(44, safeWidth / 4) // Минимум 44 для кнопки
            
            VStack(spacing: safeSpacing) {
                // Rows 1-4 в сетке 4x4
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: safeSpacing), count: 4), spacing: safeSpacing) {
                // Row 1
                iconKey("delete.left", kind: .grayTop, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.backspace) }
                key("C", kind: .grayTop, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.clearAll) }
                key("%", kind: .grayTop, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.percent) }
                iconKey("divide", kind: .accent, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.operation("/")) }
                    
                    // Row 2
                    key("7", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("7")) }
                    key("8", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("8")) }
                    key("9", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("9")) }
                    iconKey("multiply", kind: .accent, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.operation("*")) }
                    
                    // Row 3
                    key("4", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("4")) }
                    key("5", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("5")) }
                    key("6", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("6")) }
                    iconKey("minus", kind: .accent, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.operation("-")) }
                    
                    // Row 4
                    key("1", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("1")) }
                    key("2", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("2")) }
                    key("3", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendDigit("3")) }
                    iconKey("plus", kind: .accent, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.operation("+")) }
                }
                
                // Row 5 — 0 и запятая стандартного размера, = занимает 2 слота
                HStack(spacing: safeSpacing) {
                    // Кнопка 0 - стандартный размер (1 слот)
                    key("0", height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendZero) }
                        .frame(width: buttonWidth)
                    
                    // Кнопка запятой - стандартный размер (1 слот)
                    key(decSep, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.appendComma) }
                        .frame(width: buttonWidth)
                    
                    // Кнопка = - занимает 2 слота (2 колонки)
                    key("=", kind: .accent, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.equal) }
                        .frame(width: buttonWidth * 2 + safeSpacing)
                }
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
        case .dark: return Color(hex: "D9D9D9").opacity(0.2) // Светло-серый с opacity 20% для цифр
        case .gray: return Color(hex: "D9D9D9").opacity(0.2) // Светло-серый с opacity 20% для запятой
        case .grayTop: return Color(hex: "D9D9D9").opacity(0.4) // Светло-серый с opacity 40% для первых трех кнопок (удаление, C, %)
        case .accent: return Color(hex: "68A5FF").opacity(0.6) // Синий с opacity 60% для операторов и =
        }
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
