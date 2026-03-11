import SwiftUI
import Combine

enum MarketSymbolFilter: Sendable {
    case stocks
    case crypto

    var navigationTitle: LocalizedStringKey {
        switch self {
        case .stocks:
            return "finances.market.search_title_stocks"
        case .crypto:
            return "finances.market.search_title_crypto"
        }
    }

    var searchPrompt: LocalizedStringKey {
        switch self {
        case .stocks:
            return "finances.market.search_prompt_ticker"
        case .crypto:
            return "finances.market.search_prompt_pair"
        }
    }

    var instructionText: LocalizedStringKey {
        switch self {
        case .stocks:
            return "finances.market.search.instructions_stocks"
        case .crypto:
            return "finances.market.search.instructions_crypto"
        }
    }

    func matches(_ symbol: TwelveDataSymbol) -> Bool {
        guard let type = symbol.normalizedInstrumentType, !type.isEmpty else {
            return true
        }

        switch self {
        case .stocks:
            return type.contains("stock") || type.contains("equity") || type.contains("etf")
        case .crypto:
            return type.contains("crypto") || type.contains("digital") || type.contains("coin")
        }
    }
}

@MainActor
final class MarketSymbolSearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var results: [TwelveDataSymbol] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let client: MarketDataClientProtocol
    private let filter: MarketSymbolFilter
    private var searchTask: Task<Void, Never>?

    init(client: MarketDataClientProtocol, filter: MarketSymbolFilter) {
        self.client = client
        self.filter = filter
    }

    func updateSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        searchTask = Task { [client, filter] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }

                let fetched = try await client.searchSymbols(query: query)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.results = fetched.filter { filter.matches($0) }
                    self.isLoading = false
                    self.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.results = []
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelOngoingSearch() {
        searchTask?.cancel()
    }
}

struct MarketSymbolSearchSheet: View {
    let filter: MarketSymbolFilter
    let onSelect: (TwelveDataSymbol) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MarketSymbolSearchViewModel
    @State private var showSupportContactSheet = false

    init(
        filter: MarketSymbolFilter,
        client: MarketDataClientProtocol = MarketAPIClient.shared,
        onSelect: @escaping (TwelveDataSymbol) -> Void
    ) {
        self.filter = filter
        self.onSelect = onSelect
        _viewModel = StateObject(wrappedValue: MarketSymbolSearchViewModel(client: client, filter: filter))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                VStack(spacing: 16) {
                    instructionsCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    contentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(filter.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: filter.searchPrompt
            )
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.updateSearch()
            }
            .onDisappear {
                viewModel.cancelOngoingSearch()
            }
            .sheet(isPresented: $showSupportContactSheet) {
                SupportContactSheet()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView()
                .tint(AppColors.textPrimary)
        } else if let errorMessage = viewModel.errorMessage,
                  viewModel.results.isEmpty {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                Text(String(localized: "finances.market.search_hint"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.35))
            }
            .padding(.horizontal, 20)
        } else if viewModel.results.isEmpty {
            VStack(spacing: 10) {
                Text(String(localized: "finances.market.search_empty"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(String(localized: "finances.market.search_hint"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 20)
        } else {
            List {
                ForEach(viewModel.results) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(item.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                if let exchange = item.exchange,
                                   !exchange.isEmpty {
                                    Text(exchange)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }

                            Text(item.displayName)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)

                            if let currency = item.currency,
                               !currency.isEmpty {
                                Text(currency)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.instructionText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "message.badge.waveform.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("finances.market.search.support_hint")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(String(localized: "finances.market.search.contact_action")) {
                        showSupportContactSheet = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
