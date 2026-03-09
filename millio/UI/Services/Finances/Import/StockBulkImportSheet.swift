import SwiftUI
import PhotosUI
import SwiftData
import Combine

private struct StockBulkImportSearchRequest: Identifiable {
    let id: UUID
}

@MainActor
final class StockBulkImportViewModel: ObservableObject {
    @Published var mode: StockBulkImportMode = .manual
    @Published var rows: [StockBulkImportRowDraft] = []
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var includeInTotal: Bool = true
    @Published var priorityOption: StockBulkImportPriorityOption = .one
    @Published var importedCount: Int = 0
    @Published var mergeDuplicates: Bool = true
    @Published var showProblemsOnly: Bool = false

    private let parser: StockBulkImportParser
    private let matcher: StockBulkImportMatcher
    private let persistenceService: StockBulkImportPersistenceService

    init(
        modelContext: ModelContext,
        marketDataClient: MarketDataClientProtocol = TwelveDataClient.shared,
        parser: StockBulkImportParser = StockBulkImportParser()
    ) {
        self.parser = parser
        self.matcher = StockBulkImportMatcher(modelContext: modelContext, marketDataClient: marketDataClient)
        self.persistenceService = StockBulkImportPersistenceService(modelContext: modelContext, marketDataClient: marketDataClient)
    }

    var addableCount: Int {
        mergeDuplicates
            ? StockBulkImportPersistenceService.mergeAddableRows(from: rows).count
            : StockBulkImportPersistenceService.resolveAddableRows(from: rows).count
    }

    var visibleRows: [StockBulkImportRowDraft] {
        let sourceRows = showProblemsOnly
            ? rows.filter { $0.status != .found }
            : rows

        guard mergeDuplicates else {
            return sourceRows.sorted { $0.sourceOrderIndex < $1.sourceOrderIndex }
        }

        var merged: [String: StockBulkImportRowDraft] = [:]
        var order: [String] = []

        for row in sourceRows.sorted(by: { $0.sourceOrderIndex < $1.sourceOrderIndex }) {
            let mergeCandidate = row.selectedCandidate?.mergeKey ?? "\(row.market ?? "")|\(row.ticker)"
            guard !mergeCandidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                order.append(row.id.uuidString)
                merged[row.id.uuidString] = row
                continue
            }

            if var existing = merged[mergeCandidate], existing.status == .found, row.status == .found {
                let quantity = (existing.quantity ?? 0) + (row.quantity ?? 0)
                existing.quantityText = formatNumber(quantity)
                if existing.buyPrice == nil {
                    existing.buyPriceText = row.buyPriceText
                }
                merged[mergeCandidate] = existing
            } else if merged[mergeCandidate] == nil {
                merged[mergeCandidate] = row
                order.append(mergeCandidate)
            }
        }

        return order.compactMap { merged[$0] }
    }

    func analyzePhotos(items: [PhotosPickerItem]) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let limitedItems = Array(items.prefix(8))
        var imageDataList: [Data] = []
        for item in limitedItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                imageDataList.append(data)
            }
        }

        do {
            let parsedRows = try await parser.parseScreenshots(from: imageDataList)
            rows = await matcher.buildDraftRows(from: parsedRows)
            await fillCurrentPricesForMatchedRows()
            if rows.isEmpty {
                errorMessage = FinancesL10n.tr("finances.mass_import.error.no_rows")
            }
        } catch {
            errorMessage = error.localizedDescription
            rows = []
        }
    }

    func selectCandidate(_ candidate: StockBulkImportCandidate, for rowID: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        applyCandidateSelection(candidate, at: index)
    }

    func persistRows() async -> Int {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let count = try await persistenceService.persist(
                drafts: rows,
                includeInTotal: includeInTotal,
                priority: priorityOption.investmentPriority,
                targetGroup: selectedGroup,
                mergeDuplicates: mergeDuplicates
            )
            importedCount = count
            return count
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    @Published var selectedGroup: FinanceGroup?

    func addManualRow() {
        let nextIndex = (rows.map(\.sourceOrderIndex).max() ?? -1) + 1
        rows.append(
            StockBulkImportRowDraft(
                rawLine: "",
                tickerText: "",
                marketText: "",
                quantityText: "",
                buyPriceText: "",
                sourceOrderIndex: nextIndex,
                candidates: [],
                selectedCandidate: nil
            )
        )
    }

    func removeRow(_ rowID: UUID) {
        rows.removeAll { $0.id == rowID }
    }

    func updateTicker(_ value: String, for rowID: UUID) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].tickerText = sanitizeTicker(value)
        await rematchRow(at: index)
    }

    func updateMarket(_ value: String, for rowID: UUID) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].marketText = value.uppercased()
        await rematchRow(at: index)
    }

    func updateQuantity(_ value: String, for rowID: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].quantityText = value
    }

    func updateBuyPrice(_ value: String, for rowID: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].buyPriceText = value
    }

    func updateCurrentPrice(_ value: String, for rowID: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].currentPriceText = value
    }

    func clearAll() {
        rows = []
        errorMessage = nil
    }

    func applySearchResult(_ symbol: TwelveDataSymbol, for rowID: UUID) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }

        let candidate = StockBulkImportCandidate(
            symbol: symbol.symbol,
            market: symbol.exchange,
            displayName: symbol.displayName,
            currency: "USD",
            providerRaw: "twelvedata"
        )

        applyCandidateSelection(candidate, at: index)
        if rows[index].currentPriceText.isEmpty,
           let marketPrice = try? await persistenceService.marketDataClient.latestPrice(symbol: candidate.storedSymbol, forceRefresh: false) {
            rows[index].currentPriceText = formatNumber(marketPrice)
        }
    }

    private func applyCandidateSelection(_ candidate: StockBulkImportCandidate, at index: Int) {
        // Важно: после выбора инструмента синхронизируем input-поля (тикер/рынок),
        // иначе пользователю кажется, что тикер "нашёлся, но не вставился".
        rows[index].tickerText = candidate.normalizedSymbol
        rows[index].marketText = candidate.normalizedMarket ?? ""
        rows[index].candidates = [candidate]
        rows[index].selectedCandidate = candidate
    }

    private func fillCurrentPricesForMatchedRows() async {
        for index in rows.indices {
            guard rows[index].currentPriceText.isEmpty,
                  let candidate = rows[index].selectedCandidate,
                  let marketPrice = try? await persistenceService.marketDataClient.latestPrice(symbol: candidate.storedSymbol, forceRefresh: false) else {
                continue
            }
            rows[index].currentPriceText = formatNumber(marketPrice)
        }
    }

    private func rematchRow(at index: Int) async {
        let parsed = StockBulkImportParsedRow(
            rawLine: rows[index].rawLine,
            ticker: rows[index].ticker,
            market: rows[index].market,
            quantity: rows[index].quantity,
            buyPrice: rows[index].buyPrice,
            sourceOrderIndex: rows[index].sourceOrderIndex
        )
        let matched = await matcher.buildDraftRows(from: [parsed])
        guard let matchedRow = matched.first else { return }
        rows[index].candidates = matchedRow.candidates
        rows[index].selectedCandidate = matchedRow.selectedCandidate
    }

    private func sanitizeTicker(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == ":" || $0 == "-" }.prefix(24))
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct StockBulkImportSheet: View {
    private enum FocusField: Hashable {
        case ticker(UUID)
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var financeViewModel: FinanceViewModel
    @StateObject private var viewModel: StockBulkImportViewModel
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var searchRequest: StockBulkImportSearchRequest?
    @State private var showGroupCreator: Bool = false
    @State private var previousGroupIDs: Set<String> = []
    @FocusState private var focusedField: FocusField?

    init(
        financeViewModel: FinanceViewModel,
        modelContext: ModelContext,
        marketDataClient: MarketDataClientProtocol = TwelveDataClient.shared
    ) {
        self.financeViewModel = financeViewModel
        _viewModel = StateObject(
            wrappedValue: StockBulkImportViewModel(
                modelContext: modelContext,
                marketDataClient: marketDataClient
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        modePicker
                        paramsCard
                        quickSettingsCard
                        sourceCard
                        managementCard
                        previewSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle(String(localized: "finances.mass_import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "finances.common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "finances.mass_import.add_button")) {
                        Task {
                            let imported = await viewModel.persistRows()
                            guard imported > 0 else { return }
                            financeViewModel.handle(.loadAccounts)
                            financeViewModel.handle(.loadGroups)
                            dismiss()
                        }
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .disabled(viewModel.addableCount == 0 || viewModel.isProcessing)
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard viewModel.mode == .screenshot else { return }
                Task {
                    await viewModel.analyzePhotos(items: newItems)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $searchRequest) { request in
            MarketSymbolSearchSheet(filter: .stocks) { symbol in
                focusedField = nil
                Task {
                    await viewModel.applySearchResult(symbol, for: request.id)
                }
            }
        }
        .sheet(isPresented: $showGroupCreator, onDismiss: applyCreatedGroupIfNeeded) {
            FinanceGroupEditorView(viewModel: financeViewModel)
        }
    }

    private func tickerTextBinding(for rowID: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.rows.first(where: { $0.id == rowID })?.tickerText ?? "" },
            set: { newValue in
                Task { await viewModel.updateTicker(newValue, for: rowID) }
            }
        )
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.mode.title"))
            Picker("", selection: $viewModel.mode) {
                ForEach(StockBulkImportMode.allCases) { mode in
                    Text(FinancesL10n.tr(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var paramsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.params"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "finances.mass_import.group"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        HStack(spacing: 10) {
                            Menu {
                                Button(String(localized: "finances.mass_import.group_none")) {
                                    viewModel.selectedGroup = nil
                                }
                                ForEach(selectableGroups, id: \.groupUniqueID) { group in
                                    Button(group.name) {
                                        viewModel.selectedGroup = group
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(viewModel.selectedGroup?.name ?? String(localized: "finances.mass_import.group_none"))
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                                .foregroundStyle(AppColors.brandPrimary)
                            }

                            Button {
                                previousGroupIDs = Set(financeViewModel.state.groups.map(\.groupUniqueID))
                                financeViewModel.handle(.addGroup)
                                showGroupCreator = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppColors.brandPrimary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var quickSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.quick_settings"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.includeInTotal) {
                        Text(String(localized: "finances.mass_import.include_in_total"))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .tint(AppColors.brandPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    FinancesRowDivider()

                    HStack {
                        Text(String(localized: "finances.mass_import.priority"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("", selection: $viewModel.priorityOption) {
                            ForEach(StockBulkImportPriorityOption.allCases) { option in
                                Text("\(option.rawValue)").tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    @ViewBuilder
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.source.title"))

            switch viewModel.mode {
            case .manual:
                VStack(spacing: 10) {
                    Button {
                        viewModel.addManualRow()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "finances.mass_import.add_row"))
                                    .font(.system(size: 17, weight: .semibold))
                                Text(String(localized: "finances.mass_import.add_row_hint"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.72))
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppColors.brandPrimary.opacity(0.95),
                                        (AppColors.financesGradient.last ?? AppColors.brandPrimary).opacity(0.88)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    )
                    .shadow(color: AppColors.brandPrimary.opacity(0.28), radius: 18, y: 8)

                    ForEach(viewModel.rows.sorted(by: { $0.sourceOrderIndex < $1.sourceOrderIndex })) { row in
                        manualRowEditor(row)
                    }
                }
            case .screenshot:
                FinancesGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 8,
                            matching: .images
                        ) {
                            Label(
                                String(localized: "finances.mass_import.pick_screenshots"),
                                systemImage: "photo.on.rectangle.angled"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.brandPrimary)

                        Text(
                            FinancesL10n.format(
                                "finances.mass_import.screenshot_count",
                                selectedPhotoItems.count
                            )
                        )
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var managementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.management"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.mergeDuplicates) {
                        Text(String(localized: "finances.mass_import.merge_duplicates"))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .tint(AppColors.brandPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    FinancesRowDivider()

                    Toggle(isOn: $viewModel.showProblemsOnly) {
                        Text(String(localized: "finances.mass_import.show_problems"))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .tint(AppColors.brandPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    FinancesRowDivider()

                    Button(String(localized: "finances.common.reset")) {
                        viewModel.clearAll()
                    }
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(
                title: FinancesL10n.format("finances.mass_import.preview_title", viewModel.addableCount, viewModel.rows.count)
            )

            if viewModel.isProcessing {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if let errorMessage = viewModel.errorMessage {
                placeholderCard(text: errorMessage)
            } else if viewModel.visibleRows.isEmpty {
                placeholderCard(text: FinancesL10n.tr("finances.mass_import.preview_empty"))
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.visibleRows) { row in
                        editableImportedRow(row)
                    }
                }
            }
        }
    }

    private func placeholderCard(text: String) -> some View {
        FinancesGlassCard {
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editableImportedRow(_ row: StockBulkImportRowDraft) -> some View {
        FinancesGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.displayHeaderSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        if let secondary = row.displaySecondaryText {
                            Text(secondary)
                                .font(.system(size: row.shouldShowRawLineAsSecondaryText ? 12 : 13, weight: .regular))
                                .foregroundStyle(row.shouldShowRawLineAsSecondaryText ? AppColors.textSecondary : AppColors.textTertiary)
                                .lineLimit(row.shouldShowRawLineAsSecondaryText ? 2 : 1)
                        }
                    }

                    Spacer()

                    Text(FinancesL10n.tr(row.status.localizationKey))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusColor(row.status).opacity(0.16))
                        .foregroundStyle(statusColor(row.status))
                        .clipShape(Capsule())
                }

                inlineEditorGrid(for: row)
            }
            .padding(14)
        }
    }

    private func manualRowEditor(_ row: StockBulkImportRowDraft) -> some View {
        FinancesGlassCard {
            inlineEditorGrid(for: row, showsDelete: true)
            .padding(16)
        }
    }

    private func inlineEditorGrid(for row: StockBulkImportRowDraft, showsDelete: Bool = false) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField(
                    String(localized: "finances.mass_import.field_ticker"),
                    text: tickerTextBinding(for: row.id)
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .ticker(row.id))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    focusedField = nil
                    searchRequest = StockBulkImportSearchRequest(id: row.id)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.brandPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if showsDelete {
                    Button(role: .destructive) {
                        viewModel.removeRow(row.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                compactField(
                    title: String(localized: "finances.mass_import.field_market"),
                    text: Binding(
                        get: { row.marketText },
                        set: { newValue in
                            Task { await viewModel.updateMarket(newValue, for: row.id) }
                        }
                    )
                )
                compactField(
                    title: String(localized: "finances.mass_import.field_quantity"),
                    text: Binding(
                        get: { row.quantityText },
                        set: { viewModel.updateQuantity($0, for: row.id) }
                    ),
                    keyboard: .decimalPad
                )
                compactField(
                    title: String(localized: "finances.mass_import.field_buy_price"),
                    text: Binding(
                        get: { row.buyPriceText },
                        set: { viewModel.updateBuyPrice($0, for: row.id) }
                    ),
                    keyboard: .decimalPad
                )
                compactField(
                    title: String(localized: "finances.mass_import.field_current_price"),
                    text: Binding(
                        get: { row.currentPriceText },
                        set: { viewModel.updateCurrentPrice($0, for: row.id) }
                    ),
                    keyboard: .decimalPad
                )
            }

            if !row.candidates.isEmpty && row.selectedCandidate == nil {
                Menu {
                    ForEach(row.candidates) { candidate in
                        Button(candidate.storedSymbol) {
                            focusedField = nil
                            viewModel.selectCandidate(candidate, for: row.id)
                        }
                    }
                } label: {
                    HStack {
                        Text(String(localized: "finances.mass_import.choose_instrument"))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .foregroundStyle(AppColors.textPrimary)
    }

    private func compactField(title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusColor(_ status: StockBulkImportRowStatus) -> Color {
        switch status {
        case .found:
            return .green
        case .ambiguous:
            return .orange
        case .notFound:
            return .red
        }
    }

    private func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func formatNumber(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var selectableGroups: [FinanceGroup] {
        let ungroupedName = FinancesL10n.tr("finances.group.ungrouped")
        return financeViewModel.state.groups.filter { $0.name != ungroupedName }
    }

    private func applyCreatedGroupIfNeeded() {
        financeViewModel.handle(.loadGroups)
        if let createdGroup = FinanceGroupCreationDetector.detectCreatedGroup(
            previousGroupIDs: previousGroupIDs,
            groups: financeViewModel.state.groups
        ) {
            viewModel.selectedGroup = createdGroup
        }
    }
}
