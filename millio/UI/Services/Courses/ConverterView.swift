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
    @State private var historyPreviewImage: UIImage? = nil
    @State private var showHistoryPreview: Bool = false
    @State private var sharePreviewKeyboardHeight: CGFloat = 0
    
    private var decSep: String { Locale.current.decimalSeparator ?? "," }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @State private var showCryptoProAlert = false

    private let rowStrokeColor = Color.white.opacity(0.16)
    private let rowInactiveStrokeColor = Color.white.opacity(0.07)
    private let rowCornerRadius: CGFloat = 18
    private let neonCyan = Color(hex: "47D7FF")
    private let neonViolet = Color(hex: "8A6BFF")
    private let currentRoute: AppRoute = .courses
    
    
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
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            GeometryReader { geo in
                let layout = ConverterScreenLayoutCalculator.makeLayout(
                    totalHeight: geo.size.height,
                    bottomSafeArea: geo.safeAreaInsets.bottom
                )
                mainContent(layout: layout)
            }
            
            // Toast для ошибок
            VStack {
                Spacer()
                if let message = viewModel.state.toastMessage {
                    ToastView(message: message, isPresented: Binding(
                        get: { viewModel.state.showToast },
                        set: { isPresented in
                            if isPresented {
                                viewModel.state.showToast = true
                            } else {
                                viewModel.dismissToast()
                            }
                        }
                    ))
                }
            }
        }
        .task {
            viewModel.enforceCryptoAccess(allowCrypto: EntitlementPolicy.canUseConverterCrypto(isPro: appState.isPro))
            if viewModel.state.allRates.count <= 1 {
                await viewModel.fetchRates()
            }
        }
        .onChange(of: appState.isPro) { _, isPro in
            viewModel.enforceCryptoAccess(allowCrypto: EntitlementPolicy.canUseConverterCrypto(isPro: isPro))
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
        .confirmationDialog(ConverterL10n.fractionDigits, isPresented: Binding(
            get: { viewModel.state.showFractionDialog },
            set: { if !$0 { viewModel.handle(.hideFractionDialog) } }
        ), titleVisibility: .visible) {
            ForEach(0...8, id: \.self) { n in
                Button(n == viewModel.currentFractionDigits ? "\(n) ✓" : "\(n)") {
                    viewModel.handle(.setFractionDigits(n))
                }
            }
            Button(ConverterL10n.cancel, role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showSharePreviewSheet },
            set: {
                if !$0 {
                    viewModel.handle(.hideSharePreview)
                }
            }
        )) {
            sharePreviewSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showShareSheet },
            set: {
                if !$0 {
                    viewModel.state.showShareSheet = false
                }
            }
        )) {
#if os(iOS)
            if let img = viewModel.state.shareImage {
                let shareSubject = viewModel.state.shareDraftTitle.isEmpty ? ConverterL10n.shareSheetDefaultSubject : viewModel.state.shareDraftTitle
                let shareText = preparedShareText(
                    title: viewModel.state.shareDraftTitle,
                    message: viewModel.state.shareDraftMessage
                )
                ActivityView(
                    activityItems: [
                        shareText,
                        ImageItem(image: img, compressionQuality: 0.92, subject: shareSubject)
                    ],
                    onComplete: { completed in
                        let imageData = completed ? img.jpegData(compressionQuality: 0.88) : nil
                        viewModel.handle(.shareCompleted(completed, imageData))
                    }
                )
                    .ignoresSafeArea()
            }
#endif
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showShareHistorySheet },
            set: { if !$0 { viewModel.handle(.hideShareHistory) } }
        )) {
            shareHistorySheet
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveBackSwipe()
        .toolbar { topToolbar }
        .premiumUpsellAlert(
            isPresented: $showCryptoProAlert,
            titleKey: "monetization.crypto.pro_title",
            message: String(localized: "monetization.crypto.pro_message"),
            onSubscribe: { router.push(.subscription) }
        )
    }
    
    // MARK: - Split view helpers
    
    @ViewBuilder
    private func mainContent(layout: ConverterScreenLayout) -> some View {
        VStack(spacing: 0) {
            currencyList(layout: layout)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .frame(height: layout.listBlockHeight, alignment: .top)
            
            Color.clear
                .frame(height: layout.contentGap)
            
            // Клавиатура всегда внизу
            VStack(spacing: 0) {
                keypad(height: layout.keyHeight, spacing: layout.keySpacing, fontSize: layout.fontSize)
                    .padding(.horizontal, 16)
                    .frame(height: layout.keypadBlockHeight, alignment: .bottom)
            }
            .background(Color.clear)
        }
        .padding(.bottom, layout.bottomPadding)
    }
    
    @ViewBuilder
    private func currencyList(layout: ConverterScreenLayout) -> some View {
        let safeRowSpacing = layout.rowSpacing.isFinite && layout.rowSpacing >= 0 ? layout.rowSpacing : 8
        let regularRowHeight: CGFloat = layout.rowHeight
        let activeRowHeight: CGFloat = min(layout.rowHeight + 4, 76)
        
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
        let canUseCrypto = EntitlementPolicy.canUseConverterCrypto(isPro: appState.isPro)
        return NavigationStack {
            CurrencyPickerView(
                allCodes: viewModel.allAvailableCodes,
                searchText: Binding(
                    get: { viewModel.state.searchText },
                    set: { viewModel.handle(.updateSearchText($0)) }
                ),
                selectedCodes: viewModel.state.selectedCurrencies,
                badgeForCode: { code in
                    guard CurrencySelectionSupport.isCrypto(code), !canUseCrypto else { return nil }
                    return .pro
                },
                onSelect: { code in
                    if CurrencySelectionSupport.isCrypto(code),
                       !canUseCrypto {
                        viewModel.handle(.hidePicker)
                        showCryptoProAlert = true
                        return
                    }
                    viewModel.handle(.applyPickerSelection(code))
                }
            )
            .navigationTitle(viewModel.state.replaceIndex == nil ? ConverterL10n.addCurrencyTitle : ConverterL10n.replaceCurrencyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ConverterL10n.cancel) {
                        viewModel.handle(.hidePicker)
                    }
                }
            }
            .interactiveDismissDisabled(false)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            FinancesSectionHeader(title: ConverterL10n.sectionRate)
                            FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? AppColors.brandPrimary) {
                                VStack(spacing: 0) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isRateSourceExpanded.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(ConverterL10n.rateSource)
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
                                        Text(ConverterL10n.lastUpdate)
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
                                            Text(viewModel.state.isFetchingRates ? ConverterL10n.refreshingRates : ConverterL10n.refreshRates)
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
                            FinancesSectionHeader(title: ConverterL10n.sectionPrecision)
                            FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? AppColors.brandPrimary, contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(ConverterL10n.fractionDigits)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Picker(ConverterL10n.fractionDigits, selection: Binding(
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
                            FinancesSectionHeader(title: ConverterL10n.sectionFeel)
                            FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? AppColors.brandPrimary, contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                                Toggle(ConverterL10n.haptics, isOn: Binding(
                                    get: { viewModel.state.hapticsEnabled },
                                    set: { viewModel.handle(.setHapticsEnabled($0)) }
                                ))
                                .tint(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                                .foregroundStyle(AppColors.textPrimary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            FinancesSectionHeader(title: ConverterL10n.sectionWidget)
                            FinancesGlassCard(
                                accentColor: AppColors.financesGradient.first ?? AppColors.brandPrimary,
                                contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                            ) {
                                VStack(alignment: .leading, spacing: 18) {
                                    ConverterWidgetSettingsPreview()

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(ConverterL10n.widgetHowToTitle)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)

                                        VStack(alignment: .leading, spacing: 10) {
                                            ConverterWidgetInstructionRow(number: 1, text: ConverterL10n.widgetStepOpenJiggle)
                                            ConverterWidgetInstructionRow(number: 2, text: ConverterL10n.widgetStepFindMillio)
                                            ConverterWidgetInstructionRow(number: 3, text: ConverterL10n.widgetStepAddWidget)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(ConverterL10n.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ConverterL10n.settingsDone) {
                        viewModel.handle(.hideSettingsSheet)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
    
    
    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        let itemSize: CGFloat = 28
        let iconSize: CGFloat = 16

        ToolbarItem(placement: .principal) {
            EmptyView()
        }

        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: iconSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white.opacity(0.96))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(MiniAppNavigation.destinations(excluding: currentRoute)) { destination in
                        Button {
                            switchToMiniApp(destination.route)
                        } label: {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: iconSize, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white.opacity(0.90))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Быстрая навигация по мини-приложениям")
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 6) {
                Button {
                    viewModel.handle(.showShareHistory)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: iconSize + 1, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white.opacity(0.96))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ConverterL10n.shareHistoryAccessibility)

                Button {
                    guard viewModel.canRemoveCurrency else { return }
                    viewModel.handle(.removeLastCurrency)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: iconSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(viewModel.canRemoveCurrency ? Color.white.opacity(0.94) : Color.white.opacity(0.35))
                        .frame(width: itemSize, height: itemSize)
                }
                .disabled(!viewModel.canRemoveCurrency)
                .buttonStyle(.plain)
                .accessibilityLabel(ConverterL10n.removeCurrencyAccessibility)

                if viewModel.canAddCurrency {
                    Button {
                        viewModel.handle(.addCurrency)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: iconSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.white.opacity(0.94))
                            .frame(width: itemSize, height: itemSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ConverterL10n.addCurrencyAccessibility)
                }

                Button {
                    handleShareTap()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: iconSize, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ConverterL10n.shareAccessibility)

                Button {
                    viewModel.handle(.showSettingsSheet)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: iconSize, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ConverterL10n.settingsAccessibility)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }
    }

    private var shareHistorySheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if viewModel.state.shareHistory.isEmpty {
                    Text(ConverterL10n.historyEmpty)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 24)
                        .padding(.horizontal, 16)
                } else {
                    List {
                        ForEach(viewModel.state.shareHistory) { item in
                            historyRow(item: item)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.handle(.deleteShareHistoryItem(item.id))
                                    } label: {
                                        Label(ConverterL10n.delete, systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationTitle(ConverterL10n.historyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ConverterL10n.close) {
                        viewModel.handle(.hideShareHistory)
                    }
                }
            }
            .sheet(isPresented: $showHistoryPreview) {
#if os(iOS)
                historyPreviewScreen
#endif
            }
        }
    }

    private func historyRow(item: ConverterShareHistoryItem) -> some View {
        Button {
#if os(iOS)
            if let image = historyImage(for: item.imageFileName) {
                historyPreviewImage = image
                showHistoryPreview = true
            }
#endif
        } label: {
            HStack(spacing: 12) {
#if os(iOS)
                Group {
                    if let image = historyImage(for: item.imageFileName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.6))
                            )
                    }
                }
                .frame(width: 56, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
#endif
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.shareTitle ?? ConverterL10n.shareFallbackTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(shareHistoryDateText(item.createdAt))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary.opacity(0.85))
                    }
                    Text("\(item.activeCode) • \(item.inputText)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(item.selectedCodes.joined(separator: " · "))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                    if let note = item.note, !note.isEmpty {
                        Text(ConverterL10n.shareNote(note))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var sharePreviewSheet: some View {
        NavigationStack {
            GeometryReader { geometry in
                let keyboardOverlap = max(0, sharePreviewKeyboardHeight - geometry.safeAreaInsets.bottom)
                let cardScale = SharePreviewLayout.cardScale(
                    containerHeight: geometry.size.height,
                    keyboardHeight: keyboardOverlap
                )
                let compactInput = cardScale < 0.95

                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(alignment: .leading, spacing: compactInput ? 8 : 10) {
                        shareCardPreview(scale: cardScale, containerHeight: geometry.size.height, keyboardHeight: keyboardOverlap)
                        VStack(alignment: .leading, spacing: compactInput ? 8 : 10) {
                            Text(viewModel.state.shareDraftTitle)
                                .font(.system(size: compactInput ? 14 : 15, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.94))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                            TextField(
                                ConverterL10n.shareMessagePlaceholder,
                                text: Binding(
                                    get: { viewModel.state.shareDraftMessage },
                                    set: { viewModel.handle(.updateShareDraftMessage($0)) }
                                ),
                                axis: .vertical
                            )
                            .lineLimit(compactInput ? 1...3 : 2...5)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            .font(.system(size: compactInput ? 14 : 15, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .padding(.horizontal, 12)
                            .padding(.vertical, compactInput ? 8 : 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
#if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                withAnimation(.easeInOut(duration: 0.2)) {
                    sharePreviewKeyboardHeight = keyboardOverlapHeight(from: note)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    sharePreviewKeyboardHeight = 0
                }
            }
#endif
            .onDisappear {
                sharePreviewKeyboardHeight = 0
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ConverterL10n.cancel) {
                        viewModel.handle(.hideSharePreview)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(ConverterL10n.sharePreviewTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ConverterL10n.sendButton) {
                        #if os(iOS)
                        if let image = renderCurrentShareImage() {
                            viewModel.setShareImage(image)
                            viewModel.handle(.sendShareFromPreview)
                        }
                        #endif
                    }
                }
            }
        }
    }

    private func shareHistoryDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "dd MMM • HH:mm"
        return formatter.string(from: date)
    }

#if os(iOS)
    private func historyImage(for fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("ConverterShareHistory", isDirectory: true).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private var historyPreviewScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = historyPreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showHistoryPreview = false
                        historyPreviewImage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                Spacer()
            }
        }
    }

#endif
    
    private func courseRowBackground(isActive: Bool) -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [Color(hex: "1F2430"), Color(hex: "1A1F2B")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
    
    private func rowBorderStyle(isActive: Bool) -> AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [neonCyan.opacity(0.72), neonViolet.opacity(0.62)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(rowInactiveStrokeColor)
    }
    
    @ViewBuilder
    private func currencyFlagIcon(for code: String, size: CGFloat, isActive: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill(Color(hex: "141A25"))
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowBorderStyle(isActive: isActive), lineWidth: 1)
                )

            if let assetName = CurrencyFlags.assetName(for: code) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.40, height: size * 0.40)
            } else {
                let fallbackEmoji = CurrencyFlags.flag(for: code)
                if fallbackEmoji != "🏳️" {
                    Text(fallbackEmoji)
                        .font(.system(size: size * 0.24))
                } else {
                    Image("flag")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: size * 0.32, height: size * 0.32)
                }
            }
        }
        .frame(width: size, height: size)
    }
    
    
    // MARK: - Currency row
    private func currencyRow(index: Int, code: String, valueText: String, isActive: Bool, rowHeight: CGFloat) -> some View {
        let safeRowHeight = rowHeight.isFinite && rowHeight > 0 ? rowHeight : 66
        
        return HStack(spacing: 8) {
            Button {
                viewModel.handle(.replaceCurrency(index))
            } label: {
                currencyFlagIcon(for: code, size: safeRowHeight, isActive: isActive)
            }
            .buttonStyle(.plain)
            
            HStack(spacing: 14) {
                Text(code)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                if isActive {
                    Button {
                        viewModel.handle(.toggleCalcMode)
                    } label: {
                        Image(systemName: "circle.grid.3x3.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if isActive && viewModel.state.calcModeOn {
                    VStack(alignment: .trailing, spacing: 3) {
                        if !viewModel.state.expressionText.isEmpty {
                            Text(viewModel.state.expressionText)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.60))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Text(viewModel.formattedInputText)
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .padding(.trailing, 2)
                } else {
                    Text(isActive ? viewModel.formattedInputText : valueText)
                        .font(.system(size: isActive ? 18 : 17, weight: isActive ? .bold : .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Color.white.opacity(0.95))
                        .padding(.trailing, 2)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .frame(height: safeRowHeight)
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(courseRowBackground(isActive: isActive))
            )
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(rowBorderStyle(isActive: isActive), lineWidth: 1)
            )
            .shadow(
                color: isActive ? neonCyan.opacity(0.14) : .clear,
                radius: isActive ? 8 : 0,
                x: 0,
                y: 0
            )
            .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
            .onTapGesture {
                #if os(iOS)
                if viewModel.state.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    viewModel.handle(.selectCurrency(code))
                }
            }
            .contextMenu {
                Button {
#if os(iOS)
                    UIPasteboard.general.string = viewModel.displayValue(for: code) + " " + code
#endif
                } label: { Label(ConverterL10n.copyValue, systemImage: "doc.on.doc") }
                Button(role: .destructive) {
                    viewModel.handle(.removeCurrency(index))
                } label: { Label(ConverterL10n.delete, systemImage: "trash") }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.handle(.removeCurrency(index))
            } label: { Label(ConverterL10n.delete, systemImage: "trash") }
        }
    }
    
    private func placeholderRow(rowHeight: CGFloat) -> some View {
        let safeRowHeight = rowHeight.isFinite && rowHeight > 0 ? rowHeight : 66
        
        return HStack(spacing: 8) {
            Image("flag")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 24, height: 24)
                .frame(width: safeRowHeight, height: safeRowHeight)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(Color(hex: "141A25"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowInactiveStrokeColor, lineWidth: 1)
                )
            HStack {
                Spacer()
                Text(ConverterL10n.addCurrencyPlaceholder)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(height: safeRowHeight)
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "1F2430"), Color(hex: "1A1F2B")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(rowInactiveStrokeColor, lineWidth: 1)
            )
        }
        .contentShape(Rectangle())
    }
    
    
    // MARK: - Keypad (нижний ряд заполняет ширину)
    private enum KeyKind { case base, secondary, top, accent }
    
    private func materialCapsule(kind: KeyKind) -> some View {
        return Capsule(style: .continuous)
            .fill(backgroundColor(for: kind))
            .overlay(
                Group {
                    if kind == .accent {
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [neonCyan.opacity(0.72), neonViolet.opacity(0.64)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    } else {
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [neonCyan.opacity(0.62), neonViolet.opacity(0.58)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
            )
            .shadow(
                color: kind == .accent ? neonCyan.opacity(0.16) : .clear,
                radius: kind == .accent ? 7 : 0,
                x: 0,
                y: 0
            )
    }

    private func backgroundColor(for kind: KeyKind) -> Color {
        switch kind {
        case .base, .accent:
            return Color.black
        case .secondary:
            return Color(hex: "20222A")
        case .top:
            return Color(hex: "2B2D33")
        }
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
                iconKey("delete.left", kind: .top, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.backspace) }
                key("C", kind: .top, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.clearAll) }
                key("%", kind: .top, height: safeHeight, fontSize: safeFontSize) { viewModel.handle(.percent) }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
                    materialCapsule(kind: kind)
                )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .buttonStyle(NeonPressStyle())
    }
    
    @ViewBuilder
    private func key(_ title: String, kind: KeyKind = .base, height: CGFloat, fontSize: CGFloat, action: @escaping () -> Void) -> some View {
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
                    materialCapsule(kind: kind)
                )
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .buttonStyle(NeonPressStyle())
    }
    
    
    // MARK: - Share
    
    private func switchToMiniApp(_ route: AppRoute) {
        MiniAppNavigation.navigate(to: route, from: currentRoute, router: router)
    }

    private func handleShareTap() {
        viewModel.handle(.prepareShare)
    }

    private func preparedShareText(title: String, message: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty && trimmedMessage.isEmpty {
            return ConverterL10n.shareFallbackMessage
        }
        if trimmedMessage.isEmpty {
            return trimmedTitle
        }
        if trimmedTitle.isEmpty {
            return trimmedMessage
        }
        return "\(trimmedTitle)\n\(trimmedMessage)"
    }

    private func shareCardPreview(scale: CGFloat, containerHeight: CGFloat, keyboardHeight: CGFloat) -> some View {
        let shareData = viewModel.getShareData()
        let cardHeight = SharePreviewLayout.cardFrameHeight(
            containerHeight: containerHeight,
            keyboardHeight: keyboardHeight
        )
        return ShareCardView(
            dateString: shareData.dateString,
            rows: shareData.rows,
            highlightedCode: shareData.highlightedCode,
            baseSummary: ConverterL10n.baseSummary(input: viewModel.state.inputText, code: viewModel.state.activeCode),
            appStoreURLText: "https://apps.apple.com"
        )
        .scaleEffect(scale, anchor: .top)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight, alignment: .top)
        .clipped()
    }

#if os(iOS)
    private func keyboardOverlapHeight(from notification: Notification) -> CGFloat {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return 0
        }
        let screenHeight = UIScreen.main.bounds.height
        return max(0, screenHeight - frame.minY)
    }

    private func renderCurrentShareImage() -> UIImage? {
        let shareData = viewModel.getShareData()
        let screenBounds = UIScreen.main.bounds
        let size: CGSize
        if UIDevice.current.userInterfaceIdiom == .phone {
            size = CGSize(
                width: min(screenBounds.width, screenBounds.height),
                height: max(screenBounds.width, screenBounds.height)
            )
        } else {
            size = screenBounds.size
        }

        let card = ShareCardView(
            dateString: shareData.dateString,
            rows: shareData.rows,
            highlightedCode: shareData.highlightedCode,
            baseSummary: ConverterL10n.baseSummary(input: viewModel.state.inputText, code: viewModel.state.activeCode),
            appStoreURLText: "https://apps.apple.com"
        )
        .frame(width: size.width, height: size.height)

        return ShareRenderer.render(card: card, size: size, scale: UIScreen.main.scale)
    }
#endif
    
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

private struct ConverterWidgetSettingsPreview: View {
    private let previewRows: [(flag: String, title: String, value: String)] = [
        ("🇺🇸", "USD", "78.54 ₽"),
        ("🇪🇺", "EUR", "91.04 ₽"),
        ("🇹🇷", "TRY", "2.13 ₽")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ConverterL10n.widgetPreviewTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(ConverterL10n.widgetPreviewSubtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(previewRows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        Text(row.flag)
                            .font(.system(size: 22))
                            .frame(width: 30, height: 30)

                        Text(row.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))

                        Spacer(minLength: 12)

                        Text(row.value)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)

                    if index < previewRows.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(widgetCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(hex: "1CA8FF").opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color(hex: "1CA8FF").opacity(0.18), radius: 18, x: 0, y: 10)
        }
    }

    private var widgetCardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "404553"), Color(hex: "1A1D26"), Color(hex: "0E1118")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.1), Color.clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 160
            )

            LinearGradient(
                colors: [Color(hex: "27456B").opacity(0.18), Color.clear, Color.black.opacity(0.22)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private struct ConverterWidgetInstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                )

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
#endif
