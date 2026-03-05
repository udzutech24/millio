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
    @State private var isEditMode: Bool = false
    @FocusState private var focusedRowID: String?

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
                    InlineSearchBar(
                        text: $viewModel.searchText,
                        placeholder: FinancesL10n.tr("finances.audit.search.placeholder")
                    )
                        .padding(.horizontal, 16)

                    if viewModel.filteredRows.isEmpty {
                        emptyState
                    } else {
                        ScrollViewReader { proxy in
                            listSection
                                .onChange(of: focusedRowID) { _, newValue in
                                    guard let newValue else { return }
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(newValue, anchor: .center)
                                    }
                                }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle(FinancesL10n.tr("finances.audit.nav.title"))
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
                            Label(FinancesL10n.tr("finances.audit.menu.date"), systemImage: "calendar")
                        }

                        if !isEditMode {
                            Button {
                                isEditMode = true
                            } label: {
                                Label(FinancesL10n.tr("finances.audit.menu.edit_mode.start"), systemImage: "pencil")
                            }
                        } else {
                            Button {
                                isEditMode = false
                            } label: {
                                Label(FinancesL10n.tr("finances.audit.menu.edit_mode.finish"), systemImage: "checkmark")
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
                FinancesL10n.tr("finances.audit.confirmation.title"),
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                presenting: pendingAction
            ) { action in
                switch action {
                case .deleteValue(let row):
                    Button(FinancesL10n.tr("finances.audit.confirmation.delete_value"), role: .destructive) {
                        viewModel.deleteValue(for: row)
                        EventBus.shared.publish(FinanceEvent.auditSnapshotsUpdated)
                        pendingAction = nil
                    }
                case .deleteAccount(let row):
                    Button(FinancesL10n.tr("finances.audit.confirmation.delete_account"), role: .destructive) {
                        viewModel.deleteAccountForever(row)
                        EventBus.shared.publish(FinanceEvent.auditSnapshotsUpdated)
                        pendingAction = nil
                    }
                }
                Button(FinancesL10n.tr("finances.common.cancel"), role: .cancel) {}
            } message: { action in
                switch action {
                case .deleteValue(let row):
                    Text(FinancesL10n.format("finances.audit.confirmation.delete_value.message", row.title))
                case .deleteAccount(let row):
                    Text(FinancesL10n.format("finances.audit.confirmation.delete_account.message", row.title))
                }
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                amountDrafts.removeAll()
            }
            .onChange(of: isEditMode) { _, isOn in
                if !isOn { focusedRowID = nil }
            }
            .safeAreaInset(edge: .bottom) {
                if isEditMode {
                    saveBar
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
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                        Text(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 22, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.cyan.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.cyan.opacity(0.55), lineWidth: 1.0)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FinancesL10n.tr("finances.audit.accessibility.select_date"))

                Spacer()
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
                    .id(row.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingAction = .deleteValue(row)
                        } label: {
                            Label(FinancesL10n.tr("finances.audit.swipe.delete_date"), systemImage: "trash")
                        }

                        Button(role: .destructive) {
                            pendingAction = .deleteAccount(row)
                        } label: {
                            Label(FinancesL10n.tr("finances.audit.swipe.delete_account"), systemImage: "xmark.bin")
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
        let isFocused = focusedRowID == row.id

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                if row.isUnknown {
                    Text(FinancesL10n.tr("finances.audit.badge.unknown"))
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
                if isEditMode {
                    TextField(
                        "0",
                        text: Binding(
                            get: { amountDraft(for: row) },
                            set: { newValue in
                                amountDrafts[row.id] = AmountInputFormatter.sanitize(newValue, maxFractionDigits: 8)
                            }
                        )
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: 160)
                    .focused($focusedRowID, equals: row.id)
                    .submitLabel(.done)
                    .onTapGesture {
                        focusedRowID = row.id
                    }
                } else {
                    Text(money(row.value))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: 180, alignment: .trailing)
                }
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
        return AmountInputFormatter.display(draft, maxFractionDigits: 8)
    }

    private func ensureAmountDraft(for row: FinanceBalanceAuditRow) {
        guard amountDrafts[row.id] == nil else { return }
        amountDrafts[row.id] = rawNumberString(row.value)
    }

    private var saveBar: some View {
        HStack {
            Button {
                saveDrafts()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(FinancesL10n.tr("finances.audit.save"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hasChanges ? Color.green : Color.green.opacity(0.45))
            )
            .disabled(!hasChanges)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var hasChanges: Bool {
        viewModel.filteredRows.contains(where: { row in
            guard let draft = amountDrafts[row.id],
                  let parsed = AmountInputFormatter.parse(draft) else {
                return false
            }
            return abs(parsed - row.value) > 0.000_001
        })
    }

    private func saveDrafts() {
        var didSave = false
        for row in viewModel.filteredRows {
            guard let draft = amountDrafts[row.id],
                  let parsed = AmountInputFormatter.parse(draft),
                  parsed.isFinite else {
                continue
            }
            if abs(parsed - row.value) > 0.000_001 {
                viewModel.setValue(parsed, for: row)
                amountDrafts[row.id] = rawNumberString(parsed)
                didSave = true
            }
        }
        if didSave {
            EventBus.shared.publish(FinanceEvent.auditSnapshotsUpdated)
        }
        focusedRowID = nil
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.textTertiary)
            Text(FinancesL10n.tr("finances.audit.empty.no_snapshot"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Button(FinancesL10n.tr("finances.audit.empty.select_other_date")) {
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
                    FinancesL10n.tr("finances.audit.date_picker.label"),
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
            .navigationTitle(FinancesL10n.tr("finances.audit.date_picker.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(FinancesL10n.tr("finances.audit.date_picker.done")) { showDatePickerSheet = false }
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
