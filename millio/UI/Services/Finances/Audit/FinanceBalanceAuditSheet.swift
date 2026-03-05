import SwiftUI
import SwiftData

struct FinanceBalanceAuditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @ObservedObject private var financeViewModel: FinanceViewModel
    @StateObject private var viewModel: FinanceBalanceAuditViewModel

    @State private var showDatePickerSheet: Bool = false
    @State private var pendingAction: PendingAction?
    @State private var amountDrafts: [String: String] = [:]

    @AppStorage("finance.balance.audit.review.frequency") private var reviewFrequencyRaw: String = FinanceBalanceReviewFrequency.off.rawValue
    @AppStorage("finance.balance.audit.review.lastDate") private var lastReviewDateTS: Double = 0

    private enum PendingAction: Identifiable {
        case deleteValue(FinanceBalanceAuditRow)
        case deleteAccount(FinanceBalanceAuditRow)

        var id: String {
            switch self {
            case .deleteValue(let row):
                return "delete-value-\(row.id)"
            case .deleteAccount(let row):
                return "delete-account-\(row.id)"
            }
        }
    }

    init(financeViewModel: FinanceViewModel, modelContext: ModelContext) {
        self.financeViewModel = financeViewModel
        _viewModel = StateObject(
            wrappedValue: FinanceBalanceAuditViewModel(
                modelContext: modelContext,
                financeViewModel: financeViewModel
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 12) {
                    headerSection
                    InlineSearchBar(text: $viewModel.searchText, placeholder: "Поиск счёта")
                        .padding(.horizontal, 16)

                    if viewModel.filteredRows.isEmpty {
                        emptyState
                    } else {
                        listSection
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Дневные срезы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showDatePickerSheet = true
                        } label: {
                            Label("Дата", systemImage: "calendar")
                        }

                        Picker("Частота ревью", selection: $reviewFrequencyRaw) {
                            ForEach(FinanceBalanceReviewFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency.rawValue)
                            }
                        }

                        if !viewModel.isReviewMode {
                            Button {
                                viewModel.beginReview()
                                lastReviewDateTS = Date().timeIntervalSince1970
                            } label: {
                                Label("Режим ревью", systemImage: "text.cursor")
                            }
                        } else {
                            Button {
                                viewModel.stopReview()
                                lastReviewDateTS = Date().timeIntervalSince1970
                            } label: {
                                Label("Завершить ревью", systemImage: "checkmark")
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showDatePickerSheet) {
                datePickerSheet
            }
            .confirmationDialog(
                "Подтвердите действие",
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                presenting: pendingAction
            ) { action in
                switch action {
                case .deleteValue(let row):
                    Button("Удалить значение", role: .destructive) {
                        viewModel.deleteValue(for: row)
                        pendingAction = nil
                    }
                case .deleteAccount(let row):
                    Button("Удалить счёт навсегда", role: .destructive) {
                        viewModel.deleteAccountForever(row)
                        pendingAction = nil
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: { action in
                switch action {
                case .deleteValue(let row):
                    Text("Удалится только значение за выбранную дату для «\(row.title)». Операция идемпотентна.")
                case .deleteAccount(let row):
                    Text("Счёт «\(row.title)» будет удалён из истории и текущей базы. Операция необратима.")
                }
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                amountDrafts.removeAll()
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isReviewMode {
                    reviewControls
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showDatePickerSheet = true
                } label: {
                    Label(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)

                Spacer()

                if lastReviewDateTS > 0 {
                    Text("Last: \(Date(timeIntervalSince1970: lastReviewDateTS).formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            totalsGrid
        }
        .padding(.horizontal, 16)
    }

    private var totalsGrid: some View {
        VStack(spacing: 8) {
            if !viewModel.groupTotals.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.groupTotals) { item in
                            badge(title: item.groupName, value: money(item.total), tint: .cyan)
                        }
                    }
                }
            }

            if !viewModel.currencyTotals.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.currencyTotals) { item in
                            badge(title: item.currencyCode, value: money(item.total), tint: .green)
                        }
                    }
                }
            }
        }
    }

    private func badge(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 0.7)
                )
        )
    }

    private var listSection: some View {
        List {
            ForEach(viewModel.filteredRows) { row in
                rowView(row)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingAction = .deleteValue(row)
                        } label: {
                            Label("Удалить дату", systemImage: "trash")
                        }

                        Button(role: .destructive) {
                            pendingAction = .deleteAccount(row)
                        } label: {
                            Label("Удалить счёт", systemImage: "xmark.bin")
                        }
                        .tint(.red)
                    }
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    private func rowView(_ row: FinanceBalanceAuditRow) -> some View {
        let isFocused = viewModel.isFocused(row)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                if row.isUnknown {
                    Text("Неизвестный")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }

                Spacer()

                Menu {
                    ForEach(viewModel.availableCurrencies, id: \.self) { code in
                        Button(code) {
                            viewModel.setCurrency(code, for: row)
                        }
                    }
                } label: {
                    Text(row.currencyCode)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text(row.groupName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                TextField(
                    "0",
                    text: Binding(
                        get: { amountDraft(for: row) },
                        set: { newValue in
                            amountDrafts[row.id] = AmountInputFormatter.sanitize(newValue)
                            if let parsed = AmountInputFormatter.parse(newValue), parsed.isFinite {
                                viewModel.setValue(parsed, for: row)
                            }
                        }
                    )
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: 160)
            }
        }
        .onAppear {
            ensureAmountDraft(for: row)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFocused ? Color.cyan.opacity(0.16) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isFocused ? Color.cyan.opacity(0.55) : Color.white.opacity(0.14), lineWidth: 0.8)
                )
        )
    }

    private func amountDraft(for row: FinanceBalanceAuditRow) -> String {
        let draft = amountDrafts[row.id] ?? rawNumberString(row.value)
        return AmountInputFormatter.display(draft)
    }

    private func ensureAmountDraft(for row: FinanceBalanceAuditRow) {
        guard amountDrafts[row.id] == nil else { return }
        amountDrafts[row.id] = rawNumberString(row.value)
    }

    private var reviewControls: some View {
        HStack(spacing: 12) {
            Button("Назад") {
                viewModel.focusPrevious()
                lastReviewDateTS = Date().timeIntervalSince1970
            }
            .buttonStyle(.bordered)

            Button("Вперед") {
                viewModel.focusNext()
                lastReviewDateTS = Date().timeIntervalSince1970
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Button("Стоп") {
                viewModel.stopReview()
                lastReviewDateTS = Date().timeIntervalSince1970
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.35))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.textTertiary)
            Text("На эту дату нет сохраненного среза")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Button("Выбрать другую дату") {
                showDatePickerSheet = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Дата среза",
                    selection: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.setDate($0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer()
            }
            .navigationTitle("Выбор даты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { showDatePickerSheet = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func rawNumberString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
