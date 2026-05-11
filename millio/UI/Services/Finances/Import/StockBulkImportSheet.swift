import SwiftUI
import PhotosUI
import SwiftData
import Combine

private struct StockBulkImportSearchRequest: Identifiable {
    let id: UUID
}

struct StockBulkImportModePresentation: Equatable {
    let icon: String
    let title: String
    let subtitle: String
}

enum StockBulkImportLayoutPolicy {
    private static var locale: Locale { AppLocalization.currentAppLocale }

    static func presentation(for mode: StockBulkImportMode) -> StockBulkImportModePresentation {
        switch mode {
        case .screenshot:
            return StockBulkImportModePresentation(
                icon: "photo.stack",
                title: tr("finances.mass_import.pick_screenshots", fallback: "Pick up to 8 screenshots"),
                subtitle: tr(
                    "finances.mass_import.mode.screenshot.subtitle",
                    fallback: "Upload up to 8 screenshots and we will build draft positions and flag ambiguous rows."
                )
            )
        case .manual:
            return StockBulkImportModePresentation(
                icon: "square.and.pencil",
                title: tr("finances.mass_import.add_row", fallback: "Add row"),
                subtitle: tr("finances.mass_import.add_row_hint", fallback: "Fill in the position manually")
            )
        }
    }

    static func bottomActionTitle(addableCount: Int) -> String {
        addableCount > 0
            ? format(
                "finances.mass_import.bottom_action.import_format",
                fallback: "Import: %lld",
                addableCount
            )
            : tr("finances.mass_import.bottom_action.empty", fallback: "Nothing to import")
    }

    static func bottomActionSubtitle(totalRows: Int) -> String {
        totalRows > 0
            ? format(
                "finances.mass_import.bottom_action.prepared_rows_format",
                fallback: "Prepared rows: %lld",
                totalRows
            )
            : FinancesL10n.tr("finances.mass_import.preview_empty")
    }

    static var screenshotInstructionsTitle: String {
        tr("finances.mass_import.instructions.title", fallback: "How to prepare screenshots")
    }

    static var screenshotInstructionsSubtitle: String {
        tr(
            "finances.mass_import.instructions.subtitle",
            fallback: "To help the import recognize positions more accurately"
        )
    }

    static var screenshotInstructionsMessage: String {
        tr(
            "finances.mass_import.instructions.message",
            fallback: "Open your broker or portfolio screen where ticker, market, quantity, and buy price are visible\nCapture clear screenshots without heavy blur, glare, or overlays\nA light background and full position list work better than cropped cards\nYou can add up to 8 screenshots, then review the detected rows before import"
        )
    }

    static var screenshotExampleTitle: String {
        tr("finances.mass_import.example.title", fallback: "Good screenshot example")
    }

    static var screenshotExampleHint: String {
        tr(
            "finances.mass_import.example.hint",
            fallback: "Ticker, market, quantity, and buy price are readable at a glance"
        )
    }

    static var screenshotInstructionsButtonTitle: String {
        tr("finances.mass_import.instructions.button", fallback: "Got it")
    }

    static var groupHint: String {
        tr(
            "finances.mass_import.group.hint",
            fallback: "Choose the group where imported positions will be saved."
        )
    }

    static var includeInTotalHint: String {
        tr(
            "finances.mass_import.include_in_total.hint",
            fallback: "New assets will be included in the total balance right away."
        )
    }

    static var screenshotSourceHint: String {
        tr(
            "finances.mass_import.source.screenshot.hint",
            fallback: "Sharp tables and portfolio lists on a light background work best."
        )
    }

    static var mergeDuplicatesHint: String {
        tr(
            "finances.mass_import.merge_duplicates.hint",
            fallback: "Merge duplicate tickers into one final position."
        )
    }

    static var showProblemsHint: String {
        tr(
            "finances.mass_import.show_problems.hint",
            fallback: "Show only the rows that still require review."
        )
    }

    static var previewReadyTitle: String {
        tr("finances.mass_import.preview.ready", fallback: "Ready")
    }

    static var previewTotalTitle: String {
        tr("finances.mass_import.preview.total", fallback: "Total")
    }

    static var previewFilterTitle: String {
        tr("finances.mass_import.preview.filter", fallback: "Filter")
    }

    static var previewProblemsOnlyValue: String {
        tr("finances.mass_import.preview.filter.problems_only", fallback: "Problems only")
    }

    static var candidateChooseExact: String {
        tr(
            "finances.mass_import.candidate.choose_exact",
            fallback: "Choose the exact instrument from the matches below"
        )
    }

    static func candidateFoundMatches(_ count: Int) -> String {
        format(
            "finances.mass_import.candidate.found_matches_format",
            fallback: "Found %lld matches",
            count
        )
    }

    static var candidateTapToChoose: String {
        tr(
            "finances.mass_import.candidate.tap_to_choose",
            fallback: "Tap to choose instrument"
        )
    }

    private static func tr(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }

    private static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(
            format: tr(key, fallback: fallback),
            locale: locale,
            arguments: arguments
        )
    }
}

@MainActor
final class StockBulkImportViewModel: ObservableObject {
    @Published var mode: StockBulkImportMode = .screenshot
    @Published var rows: [StockBulkImportRowDraft] = []
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var includeInTotal: Bool = true
    @Published var priorityOption: StockBulkImportPriorityOption = .one
    @Published var importedCount: Int = 0
    @Published var mergeDuplicates: Bool = true
    @Published var showProblemsOnly: Bool = false
    @Published var marketDataWarning: String?
    @Published private(set) var refreshingRowIDs: Set<UUID> = []

    private struct QuoteIssue: Sendable {
        let symbol: String
        let category: MarketDataIssueCategory
    }

    private var quoteIssuesByRowID: [UUID: QuoteIssue] = [:]
    private let parser: StockBulkImportParser
    private let matcher: StockBulkImportMatcher
    private let persistenceService: StockBulkImportPersistenceService

    init(
        modelContext: ModelContext,
        marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared,
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
            ? rows.filter(\.requiresAttention)
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

            if var existing = merged[mergeCandidate],
               existingSelectedForMerge(existing),
               existingSelectedForMerge(row) {
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
        clearQuoteWarnings()
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
        quoteIssuesByRowID.removeValue(forKey: rowID)
        syncMarketDataWarning()
    }

    func removeVisibleRow(_ row: StockBulkImportRowDraft) {
        guard mergeDuplicates,
              let mergeKey = row.selectedCandidate?.mergeKey,
              !mergeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            removeRow(row.id)
            return
        }

        let matchingIDs: Set<UUID> = Set(
            rows.compactMap { sourceRow in
                guard existingSelectedForMerge(sourceRow),
                      sourceRow.selectedCandidate?.mergeKey == mergeKey else {
                    return nil
                }
                return sourceRow.id
            }
        )

        guard !matchingIDs.isEmpty else {
            removeRow(row.id)
            return
        }

        rows.removeAll { matchingIDs.contains($0.id) }
        for rowID in matchingIDs {
            quoteIssuesByRowID.removeValue(forKey: rowID)
        }
        syncMarketDataWarning()
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
        clearQuoteWarnings()
    }

    func applySearchResult(_ symbol: TwelveDataSymbol, for rowID: UUID) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }

        let candidate = StockBulkImportCandidate(
            symbol: symbol.symbol,
            market: symbol.exchange,
            displayName: symbol.displayName,
            currency: "USD",
            providerRaw: "market-backend"
        )

        applyCandidateSelection(candidate, at: index)
        if rows[index].currentPriceText.isEmpty,
           let marketPrice = await fetchLatestPrice(for: candidate, rowID: rowID, forceRefresh: false) {
            rows[index].currentPriceText = formatNumber(marketPrice)
        }
    }

    func refreshCurrentPrice(for rowID: UUID) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }),
              let candidate = rows[index].selectedCandidate,
              !refreshingRowIDs.contains(rowID) else {
            return
        }

        refreshingRowIDs.insert(rowID)
        defer { refreshingRowIDs.remove(rowID) }

        if let marketPrice = await fetchLatestPrice(for: candidate, rowID: rowID, forceRefresh: true) {
            rows[index].currentPriceText = formatNumber(marketPrice)
        } else {
            rows[index].currentPriceText = ""
        }
    }

    func isRefreshingPrice(for rowID: UUID) -> Bool {
        refreshingRowIDs.contains(rowID)
    }

    private func applyCandidateSelection(_ candidate: StockBulkImportCandidate, at index: Int) {
        // Важно: после выбора инструмента синхронизируем input-поля (тикер/рынок),
        // иначе пользователю кажется, что тикер "нашёлся, но не вставился".
        quoteIssuesByRowID.removeValue(forKey: rows[index].id)
        syncMarketDataWarning()
        rows[index].tickerText = candidate.normalizedSymbol
        rows[index].marketText = candidate.normalizedMarket ?? ""
        rows[index].candidates = [candidate]
        rows[index].selectedCandidate = candidate
    }

    private func fillCurrentPricesForMatchedRows() async {
        for index in rows.indices {
            guard rows[index].currentPriceText.isEmpty,
                  let candidate = rows[index].selectedCandidate,
                  let marketPrice = await fetchLatestPrice(for: candidate, rowID: rows[index].id, forceRefresh: false) else {
                continue
            }
            rows[index].currentPriceText = formatNumber(marketPrice)
        }
    }

    private func fetchLatestPrice(for candidate: StockBulkImportCandidate, rowID: UUID, forceRefresh: Bool) async -> Double? {
        var lastIssueCategory: MarketDataIssueCategory?

        for symbol in candidate.quoteLookupSymbols {
            do {
                guard let latestQuote = try await persistenceService.marketDataClient.latestQuote(
                    symbol: symbol,
                    forceRefresh: forceRefresh
                ) else {
                    continue
                }

                if let issueCategory = MarketDataErrorPresentation.category(for: latestQuote) {
                    lastIssueCategory = issueCategory
                    quoteIssuesByRowID[rowID] = QuoteIssue(
                        symbol: candidate.normalizedSymbol,
                        category: issueCategory
                    )
                    syncMarketDataWarning()
                    continue
                }

                quoteIssuesByRowID.removeValue(forKey: rowID)
                syncMarketDataWarning()
                return latestQuote.price
            } catch {
                lastIssueCategory = MarketDataErrorPresentation.category(for: error)
                quoteIssuesByRowID[rowID] = QuoteIssue(
                    symbol: candidate.normalizedSymbol,
                    category: lastIssueCategory ?? .clientError
                )
                syncMarketDataWarning()
                continue
            }
        }

        quoteIssuesByRowID[rowID] = QuoteIssue(
            symbol: candidate.normalizedSymbol,
            category: lastIssueCategory ?? .notFound
        )
        syncMarketDataWarning()
        return nil
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
        quoteIssuesByRowID.removeValue(forKey: rows[index].id)
        syncMarketDataWarning()
        rows[index].candidates = matchedRow.candidates
        rows[index].selectedCandidate = matchedRow.selectedCandidate
    }

    private func clearQuoteWarnings() {
        quoteIssuesByRowID = [:]
        marketDataWarning = nil
    }

    private func syncMarketDataWarning() {
        guard !quoteIssuesByRowID.isEmpty else {
            marketDataWarning = nil
            return
        }

        let grouped = Dictionary(grouping: quoteIssuesByRowID.values, by: \.category)
        let orderedCategories: [MarketDataIssueCategory] = [
            .notFound,
            .priceUnavailable,
            .providerError,
            .authError,
            .networkError,
            .httpError,
            .decodeError,
            .clientError
        ]

        let parts = orderedCategories.compactMap { category -> String? in
            guard let issues = grouped[category], !issues.isEmpty else { return nil }
            let symbols = Array(Set(issues.map(\.symbol))).sorted()
            let label = MarketDataErrorPresentation.listLabel(for: category)
            return "\(label): \(symbols.joined(separator: ", "))"
        }

        marketDataWarning = parts.joined(separator: ". ")
    }

    private func sanitizeTicker(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == ":" || $0 == "-" }.prefix(24))
    }

    private func existingSelectedForMerge(_ row: StockBulkImportRowDraft) -> Bool {
        row.selectedCandidate != nil
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
    @State private var showScreenshotInstructions: Bool = false
    @State private var previousGroupIDs: Set<String> = []
    @FocusState private var focusedField: FocusField?

    init(
        financeViewModel: FinanceViewModel,
        modelContext: ModelContext,
        marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared
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

                screenshotInstructionsOverlay
            }
            .navigationTitle(FinancesL10n.tr("finances.mass_import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.88), value: showScreenshotInstructions)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityLabel(Text(L("finances.common.cancel")))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScreenshotInstructions = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel(Text(StockBulkImportLayoutPolicy.screenshotInstructionsTitle))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            let imported = await viewModel.persistRows()
                            guard imported > 0 else { return }
                            financeViewModel.handle(.loadAccounts)
                            financeViewModel.handle(.loadGroups)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .foregroundStyle(viewModel.addableCount > 0 ? Color.green : AppColors.textSecondary)
                    .disabled(viewModel.addableCount == 0 || viewModel.isProcessing)
                    .accessibilityLabel(Text(FinancesL10n.tr("finances.mass_import.add_button")))
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

    @ViewBuilder
    private var screenshotInstructionsOverlay: some View {
        if showScreenshotInstructions {
            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showScreenshotInstructions = false
                    }

                VStack(spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(StockBulkImportLayoutPolicy.screenshotInstructionsTitle)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)

                            Text(
                                StockBulkImportLayoutPolicy.screenshotInstructionsSubtitle
                            )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()

                        Button {
                            showScreenshotInstructions = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    screenshotExampleCard

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(screenshotInstructionLines.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppColors.brandPrimary)
                                    .frame(width: 18, alignment: .leading)

                                Text(screenshotInstructionLines[index])
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Button {
                        showScreenshotInstructions = false
                    } label: {
                        Text(StockBulkImportLayoutPolicy.screenshotInstructionsButtonTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppColors.brandPrimary.opacity(0.5), lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.08, green: 0.08, blue: 0.1),
                                    Color.black
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(AppColors.brandPrimary.opacity(0.38), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 22)
                .shadow(color: Color.black.opacity(0.32), radius: 26, y: 16)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    )
                )
            }
            .zIndex(5)
        }
    }

    private var screenshotExampleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(StockBulkImportLayoutPolicy.screenshotExampleTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(StockBulkImportLayoutPolicy.screenshotExampleHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
            }

            VStack(spacing: 8) {
                screenshotExampleRow(symbol: "AAPL", market: "NASDAQ", quantity: "12", price: "$188")
                screenshotExampleRow(symbol: "GLD", market: "NYSEARCA", quantity: "4", price: "$344")
                screenshotExampleRow(symbol: "ORCL", market: "NYSE", quantity: "7", price: "$151")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func screenshotExampleRow(symbol: String, market: String, quantity: String, price: String) -> some View {
        HStack(spacing: 8) {
            exampleCell(symbol, width: 68, alignment: .leading)
            exampleCell(market, width: 90, alignment: .leading)
            exampleCell(quantity, width: 48, alignment: .center)
            exampleCell(price, width: 58, alignment: .trailing)
        }
    }

    private func exampleCell(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 7)
            .padding(.horizontal, 7)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var screenshotInstructionLines: [String] {
        StockBulkImportLayoutPolicy.screenshotInstructionsMessage.components(separatedBy: "\n")
    }

    private func tickerTextBinding(for rowID: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.rows.first(where: { $0.id == rowID })?.tickerText ?? "" },
            set: { newValue in
                Task { await viewModel.updateTicker(newValue, for: rowID) }
            }
        )
    }

    private var modePresentation: StockBulkImportModePresentation {
        StockBulkImportLayoutPolicy.presentation(for: viewModel.mode)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.mode.title"))
            FinancesGlassCard(accentColor: AppColors.brandPrimary.opacity(0.9), cornerRadius: 20) {
                HStack(spacing: 8) {
                    ForEach(StockBulkImportMode.allCases) { mode in
                        let isSelected = viewModel.mode == mode
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                viewModel.mode = mode
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: StockBulkImportLayoutPolicy.presentation(for: mode).icon)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(FinancesL10n.tr(mode.titleKey))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(isSelected ? Color.white : AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(isSelected ? 0.16 : 0.001))
                                    .overlay {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        }
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var modeHeroCard: some View {
        Button {
            if viewModel.mode == .manual {
                viewModel.addManualRow()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 52, height: 52)
                    Image(systemName: viewModel.mode == .manual ? "plus" : modePresentation.icon)
                        .font(.system(size: viewModel.mode == .manual ? 22 : 20, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(modePresentation.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.leading)
                    Text(modePresentation.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: viewModel.mode == .manual ? "arrow.right" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.55), lineWidth: 1)
                }
        }
        .disabled(viewModel.mode != .manual)
    }

    private var paramsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.params"))
            FinancesGlassCard(accentColor: AppColors.brandPrimary.opacity(0.9), cornerRadius: 20) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FinancesL10n.tr("finances.mass_import.group"))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(
                                StockBulkImportLayoutPolicy.groupHint
                            )
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Menu {
                                Button(FinancesL10n.tr("finances.mass_import.group_none")) {
                                    viewModel.selectedGroup = nil
                                }
                                ForEach(selectableGroups, id: \.groupUniqueID) { group in
                                    Button(group.name) {
                                        viewModel.selectedGroup = group
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(viewModel.selectedGroup?.name ?? FinancesL10n.tr("finances.mass_import.group_none"))
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                                .font(.system(size: 17, weight: .semibold))
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
            FinancesGlassCard(accentColor: AppColors.brandPrimary.opacity(0.9), cornerRadius: 20) {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.includeInTotal) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FinancesL10n.tr("finances.mass_import.include_in_total"))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(
                                StockBulkImportLayoutPolicy.includeInTotalHint
                            )
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .tint(AppColors.brandPrimary)
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
                    modeHeroCard

                    ForEach(viewModel.rows.sorted(by: { $0.sourceOrderIndex < $1.sourceOrderIndex })) { row in
                        manualRowEditor(row)
                    }
                }
            case .screenshot:
                FinancesGlassCard(accentColor: AppColors.brandPrimary.opacity(0.9), cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 8,
                            matching: .images
                        ) {
                            Label(
                                FinancesL10n.tr("finances.mass_import.pick_screenshots"),
                                systemImage: "photo.on.rectangle.angled"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppColors.brandPrimary.opacity(0.55), lineWidth: 1)
                        }

                        Text(
                            FinancesL10n.format(
                                "finances.mass_import.screenshot_count",
                                selectedPhotoItems.count
                            )
                        )
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)

                        Text(
                            StockBulkImportLayoutPolicy.screenshotSourceHint
                        )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var managementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: FinancesL10n.tr("finances.mass_import.management"))
            FinancesGlassCard(accentColor: AppColors.brandPrimary.opacity(0.9), cornerRadius: 20) {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.mergeDuplicates) {
                        settingsToggleContent(
                            title: FinancesL10n.tr("finances.mass_import.merge_duplicates"),
                            subtitle: StockBulkImportLayoutPolicy.mergeDuplicatesHint
                        )
                    }
                    .tint(AppColors.brandPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    FinancesRowDivider()

                    Toggle(isOn: $viewModel.showProblemsOnly) {
                        settingsToggleContent(
                            title: FinancesL10n.tr("finances.mass_import.show_problems"),
                            subtitle: StockBulkImportLayoutPolicy.showProblemsHint
                        )
                    }
                    .tint(AppColors.brandPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    FinancesRowDivider()

                    Button(L("finances.common.reset")) {
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

            previewSummaryStrip

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
                    if let marketDataWarning = viewModel.marketDataWarning {
                        placeholderCard(text: marketDataWarning)
                    }
                    ForEach(viewModel.visibleRows) { row in
                        editableImportedRow(row)
                    }
                }
            }
        }
    }

    private var previewSummaryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                previewChip(
                    title: StockBulkImportLayoutPolicy.previewReadyTitle,
                    value: "\(viewModel.addableCount)",
                    accent: AppColors.brandPrimary
                )
                previewChip(
                    title: StockBulkImportLayoutPolicy.previewTotalTitle,
                    value: "\(viewModel.rows.count)",
                    accent: Color.white.opacity(0.9)
                )
                if viewModel.showProblemsOnly {
                    previewChip(
                        title: StockBulkImportLayoutPolicy.previewFilterTitle,
                        value: StockBulkImportLayoutPolicy.previewProblemsOnlyValue,
                        accent: AppColors.warning
                    )
                }
            }
        }
    }

    private func placeholderCard(text: String) -> some View {
        FinancesGlassCard(accentColor: AppColors.brandPrimary.opacity(0.7), cornerRadius: 20) {
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editableImportedRow(_ row: StockBulkImportRowDraft) -> some View {
        FinancesGlassCard(accentColor: statusColor(row.status), cornerRadius: 20) {
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

                    Text(row.status.localizedLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusColor(row.status).opacity(0.16))
                        .foregroundStyle(statusColor(row.status))
                        .clipShape(Capsule())
                }

                inlineEditorGrid(for: row, showsDelete: true)
            }
            .padding(14)
        }
    }

    private func manualRowEditor(_ row: StockBulkImportRowDraft) -> some View {
        FinancesGlassCard(accentColor: AppColors.brandPrimary.opacity(0.9), cornerRadius: 20) {
            inlineEditorGrid(for: row, showsDelete: true)
            .padding(16)
        }
    }

    private func inlineEditorGrid(for row: StockBulkImportRowDraft, showsDelete: Bool = false) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField(
                    FinancesL10n.tr("finances.mass_import.field_ticker"),
                    text: tickerTextBinding(for: row.id)
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .ticker(row.id))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if row.selectedCandidate != nil {
                    Button {
                        focusedField = nil
                        Task {
                            await viewModel.refreshCurrentPrice(for: row.id)
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 40, height: 40)

                            if viewModel.isRefreshingPrice(for: row.id) {
                                ProgressView()
                                    .tint(AppColors.brandPrimary)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.brandPrimary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshingPrice(for: row.id))
                } else {
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
                }

                if showsDelete {
                    Button(role: .destructive) {
                        viewModel.removeVisibleRow(row)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L("finances.common.delete")))
                }
            }

            HStack(spacing: 10) {
                compactField(
                    title: FinancesL10n.tr("finances.mass_import.field_market"),
                    text: Binding(
                        get: { row.marketText },
                        set: { newValue in
                            Task { await viewModel.updateMarket(newValue, for: row.id) }
                        }
                    )
                )
                compactField(
                    title: FinancesL10n.tr("finances.mass_import.field_quantity"),
                    text: Binding(
                        get: { row.quantityText },
                        set: { viewModel.updateQuantity($0, for: row.id) }
                    ),
                    keyboard: .decimalPad
                )
                compactField(
                    title: FinancesL10n.tr("finances.mass_import.field_buy_price"),
                    text: Binding(
                        get: { row.buyPriceText },
                        set: { viewModel.updateBuyPrice($0, for: row.id) }
                    ),
                    keyboard: .decimalPad
                )
                compactField(
                    title: FinancesL10n.tr("finances.mass_import.field_current_price"),
                    text: Binding(
                        get: { row.currentPriceText },
                        set: { viewModel.updateCurrentPrice($0, for: row.id) }
                    ),
                    keyboard: .decimalPad
                )
            }

            if !row.candidates.isEmpty && row.selectedCandidate == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        StockBulkImportLayoutPolicy.candidateChooseExact
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                    Menu {
                        ForEach(row.candidates) { candidate in
                            Button {
                                focusedField = nil
                                viewModel.selectCandidate(candidate, for: row.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidateChoiceTitle(candidate))
                                    if let subtitle = candidateChoiceSubtitle(candidate) {
                                        Text(subtitle)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(
                                    StockBulkImportLayoutPolicy.candidateFoundMatches(row.candidates.count)
                                )
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)

                                Text(
                                    StockBulkImportLayoutPolicy.candidateTapToChoose
                                )
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
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

    private func settingsToggleContent(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func previewChip(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.5), lineWidth: 1)
                }
        }
    }

    private func candidateChoiceTitle(_ candidate: StockBulkImportCandidate) -> String {
        if let market = candidate.normalizedMarket, !market.isEmpty {
            return "\(candidate.normalizedSymbol) - \(market)"
        }
        return candidate.normalizedSymbol
    }

    private func candidateChoiceSubtitle(_ candidate: StockBulkImportCandidate) -> String? {
        let displayName = candidate.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = candidate.currency.trimmingCharacters(in: .whitespacesAndNewlines)

        if !displayName.isEmpty, !currency.isEmpty {
            return "\(displayName) • \(currency)"
        }
        if !displayName.isEmpty {
            return displayName
        }
        if !currency.isEmpty {
            return currency
        }
        return nil
    }

    private var bottomActionBar: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    let imported = await viewModel.persistRows()
                    guard imported > 0 else { return }
                    financeViewModel.handle(.loadAccounts)
                    financeViewModel.handle(.loadGroups)
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(StockBulkImportLayoutPolicy.bottomActionTitle(addableCount: viewModel.addableCount))
                            .font(.system(size: 17, weight: .bold))
                        Text(StockBulkImportLayoutPolicy.bottomActionSubtitle(totalRows: viewModel.rows.count))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }

                    Spacer()

                    Image(systemName: viewModel.isProcessing ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.02))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                (viewModel.addableCount > 0 ? AppColors.brandPrimary : AppColors.textSecondary)
                                    .opacity(0.45),
                                lineWidth: 1
                            )
                    }
            }
            .disabled(viewModel.addableCount == 0 || viewModel.isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
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
        case .priceMissing:
            return .red
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
