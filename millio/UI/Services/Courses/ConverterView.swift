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
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 4
        
        // Минимальные размеры для клавиатуры
        let minKeyHeight: CGFloat = 44
        let minKeySpacing: CGFloat = 6
        let keypadRows: Int = 5
        
        // Вычисляем минимальную высоту клавиатуры
        let minKeypadHeight = CGFloat(keypadRows) * minKeyHeight + CGFloat(keypadRows - 1) * minKeySpacing + bottomSafe + bottomPadding
        
        // Доступная высота для контента (исключая header и клавиатуру)
        let availableForContent = totalH - headerH - minKeypadHeight - topPadding
        
        // Адаптируем размеры клавиатуры под доступное место
        let keypadAvailableHeight = totalH - headerH - availableForContent - topPadding - bottomPadding
        
        // Вычисляем размеры кнопок и отступы с учетом доступного места
        let keypadContentHeight = keypadAvailableHeight - bottomSafe - bottomPadding
        let keyH = max(minKeyHeight, floor((keypadContentHeight - CGFloat(keypadRows - 1) * minKeySpacing) / CGFloat(keypadRows)))
        
        // Адаптируем spacing между кнопками
        let actualKeypadContentHeight = CGFloat(keypadRows) * keyH
        let remainingSpace = keypadContentHeight - actualKeypadContentHeight
        let keySpacing = minKeySpacing + (remainingSpace > 0 ? floor(remainingSpace / CGFloat(keypadRows - 1)) : 0)
        
        // Размер шрифта зависит от высоты кнопки
        let fontSize: CGFloat = keyH >= 60 ? 22 : (keyH >= 54 ? 20 : (keyH >= 48 ? 18 : 16))
        
        // Для списка валют используем адаптивную высоту строк
        let desiredRows: Int = 6
        let rowSpacing: CGFloat = 8
        let minRowHeight: CGFloat = 58
        let maxRowHeight: CGFloat = 80
        
        // Вычисляем высоту строки списка валют
        let listAvailableHeight = max(availableForContent - topPadding * 2, minRowHeight * CGFloat(desiredRows))
        let rowH = min(maxRowHeight, max(minRowHeight, floor((listAvailableHeight - CGFloat(desiredRows - 1) * rowSpacing) / CGFloat(desiredRows))))
        
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
            GradientBackground(
                topGradientColor: "F78C3B",
                topGradientFadeColor: "1942E6",
                bottomGradientColor: "1942E6",
                bottomGradientFadeColor: "F78C3B"
            )
            
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
            // Список валют с возможностью скролла
            ScrollView {
                currencyList(layout: layout)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            
            // Клавиатура всегда внизу
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
            .interactiveDismissDisabled(false)
        }
    }
    
    
    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    Section {
                        DisclosureGroup {
                            ForEach(RateSource.allCases) { src in
                                Button {
                                    viewModel.handle(.setRateSource(src))
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(src.title)
                                                .font(.body)
                                                .foregroundStyle(AppColors.textPrimary)
                                            Text(src.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                        Spacer()
                                        if src == viewModel.state.rateSource {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: AppColors.coursesGradient,
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } label: {
                            HStack {
                                Text("Источник курса")
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                Text(viewModel.state.rateSource.title)
                                    .font(.subheadline)
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        
                        HStack {
                            Text("Последнее обновление")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text(viewModel.lastUpdatedText)
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        
                        Button {
                            #if os(iOS)
                            if viewModel.state.hapticsEnabled {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            #endif
                            viewModel.handle(.refreshRates(force: true))
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Обновить курсы")
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.coursesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                        .disabled(viewModel.state.isFetchingRates)
                    } header: {
                        Text("Курс")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    
                    Section {
                        Picker("Знаков после запятой", selection: Binding(
                            get: { viewModel.state.fractionDigits },
                            set: { viewModel.handle(.setFractionDigits($0)) }
                        )) {
                            ForEach(0...8, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Точность")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    
                    Section {
                        Toggle("Тактильный отклик", isOn: Binding(
                            get: { viewModel.state.hapticsEnabled },
                            set: { viewModel.handle(.setHapticsEnabled($0)) }
                        ))
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Ощущения")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
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
    
    
    // MARK: - Currency row
    private func currencyRow(index: Int, code: String, valueText: String, isActive: Bool, rowHeight: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.handle(.replaceCurrency(index))
            } label: {
                Text(CurrencySelectionSupport.emoji(for: code))
                    .font(.system(size: 20))
                    .frame(width: 60, height: rowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
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
                .frame(width: 60, height: rowHeight)
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
            let buttonWidth = (geometry.size.width - spacing * 3) / 4
            
            VStack(spacing: spacing) {
                // Rows 1-4 в сетке 4x4
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 4), spacing: spacing) {
                // Row 1
                iconKey("delete.left", kind: .gray, height: height, fontSize: fontSize) { viewModel.handle(.backspace) }
                key("C", kind: .gray, height: height, fontSize: fontSize) { viewModel.handle(.clearAll) }
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
                
                // Row 5 — 0 и запятая стандартного размера, = занимает 2 слота
                HStack(spacing: spacing) {
                    // Кнопка 0 - стандартный размер (1 слот)
                    key("0", height: height, fontSize: fontSize) { viewModel.handle(.appendZero) }
                        .frame(width: buttonWidth)
                    
                    // Кнопка запятой - стандартный размер (1 слот)
                    key(decSep, height: height, fontSize: fontSize) { viewModel.handle(.appendComma) }
                        .frame(width: buttonWidth)
                    
                    // Кнопка = - занимает 2 слота (2 колонки)
                    key("=", kind: .accent, height: height, fontSize: fontSize) { viewModel.handle(.equal) }
                        .frame(width: buttonWidth * 2 + spacing)
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
        case .gray: return Color(hex: "D9D9D9").opacity(0.2) // Светло-серый с opacity 20% для C, %, запятой, удаления
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

