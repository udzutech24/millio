import SwiftData
import SwiftUI

struct CashflowStatementReviewView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @ObservedObject var controller: CashflowStatementImportController
    let month: Date
    @Environment(\.modelContext) private var modelContext
    @State private var filter: CashflowStatementReviewFilter = .needsAttention
    @State private var searchText = ""
    @State private var showConfirmation = false

    private var rows: [CashflowStatementReviewRow] {
        let filtered = CashflowStatementReviewPresentationBuilder.rows(controller.reviewRows, filter: filter)
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter { $0.operation.description.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(month.formatted(.dateTime.month(.wide).year().locale(AppLocalization.currentAppLocale)))
                            .font(.headline)
                        Text("Выписка будет добавлена только в этот месяц")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let preview = controller.preview {
                    Label(
                        preview.reconciliation.balanced ? "Сверка выписки пройдена" : "Сверка требует внимания",
                        systemImage: preview.reconciliation.balanced ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(preview.reconciliation.balanced ? .green : .orange)
                }
            }

            Picker("Режим проверки", selection: $filter) {
                Text("Требуют внимания").tag(CashflowStatementReviewFilter.needsAttention)
                Text("Категории").tag(CashflowStatementReviewFilter.categories)
                Text("Все").tag(CashflowStatementReviewFilter.all)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if filter == .categories {
                categoryGroups
            } else {
                operationRows
            }
        }
        .searchable(text: $searchText, prompt: "Найти операцию")
        .navigationTitle("Проверка выписки")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                showConfirmation = true
            } label: {
                Label("Импортировать \(controller.includedFingerprints.count) операций", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.includedFingerprints.isEmpty)
            .accessibilityHint(controller.includedFingerprints.isEmpty ? "Нет операций, доступных для импорта" : "Открывает итоговое подтверждение")
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showConfirmation) {
            CashflowStatementConfirmationView(
                viewModel: viewModel,
                controller: controller,
                month: month,
                apply: applyReviewed
            )
        }
    }

    @ViewBuilder
    private var operationRows: some View {
        if rows.isEmpty {
            ContentUnavailableView("Всё проверено", systemImage: "checkmark.circle", description: Text("Операций, требующих внимания, нет."))
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(rows) { row in rowView(row) }
            }
            transferActions
        }
    }

    private var categoryGroups: some View {
        ForEach(CashflowStatementReviewPresentationBuilder.groups(rows: controller.reviewRows)) { group in
            Section {
                DisclosureGroup {
                    ForEach(group.rows) { row in rowView(row) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(categoryTitle(group.key.categoryRaw, kind: group.key.kind))
                            Text("\(group.rows.count) операций")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(group.amount, format: .currency(code: group.key.currency))
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: CashflowStatementReviewRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.operation.description).lineLimit(2)
                    Text(row.operation.operationDate).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(row.amount, format: .currency(code: row.currency))
                    .font(.body.monospacedDigit())
            }
            dispositionControls(row)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func dispositionControls(_ row: CashflowStatementReviewRow) -> some View {
        switch row.disposition {
        case .included(let kind):
            Picker("Категория", selection: Binding(
                get: { controller.categoryByFingerprint[row.id] ?? "other" },
                set: { controller.setCategory($0, for: row.operation) }
            )) {
                ForEach(viewModel.categoryOptions(for: kind), id: \.rawValue) { option in
                    Label(option.displayName, systemImage: option.icon).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
        case .excludedExternalTransfer:
            HStack {
                Label("Перевод исключён", systemImage: "arrow.left.arrow.right")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Преобразовать") {
                    Button("В расход") { controller.reclassifyExternalTransfer(row.operation, as: .expense, categoryRaw: "other") }
                    Button("В доход") { controller.reclassifyExternalTransfer(row.operation, as: .income, categoryRaw: "other") }
                }
            }
        case .excludedInternalTransfer:
            Label("Внутренний перевод нельзя импортировать как доход или расход", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
        case .excludedDuplicate:
            Label("Дубликат — операция уже существует", systemImage: "doc.on.doc")
                .font(.caption).foregroundStyle(.secondary)
        case .excludedTechnical:
            Label("Техническая строка исключена", systemImage: "gearshape")
                .font(.caption).foregroundStyle(.secondary)
        case .excludedByUser:
            Label("Исключено пользователем", systemImage: "minus.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transferActions: some View {
        if controller.reviewRows.contains(where: { $0.operation.type.hasPrefix("transfer_") }) {
            Section {
                Button("Исключить все переводы") { controller.excludeAllTransfers() }
            }
        }
    }

    private func categoryTitle(_ raw: String, kind: CashflowCategoryKind) -> String {
        viewModel.categoryOption(for: raw, kind: kind).displayName
    }

    private func applyReviewed(accountID: String?) {
        guard let preview = controller.preview else { return }
        if let accountID {
            viewModel.handle(.loadCards)
            let options = CashflowStatementAccountSelectionPolicy.options(
                cards: viewModel.state.availableCards,
                newCoreAccounts: viewModel.newCoreAccountsForCashflowPicker(),
                statementCurrencies: Set(controller.reviewRows.filter(\.disposition.isIncluded).map(\.currency))
            )
            guard CashflowStatementAccountSelectionPolicy.isValid(accountID, in: options) else {
                controller.markApplyFailure()
                return
            }
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let operations = preview.operations.compactMap { operation -> CashflowApprovedStatementOperation? in
            guard controller.includedFingerprints.contains(operation.fingerprint),
                  let disposition = controller.dispositionByFingerprint[operation.fingerprint],
                  let kind = disposition.kind,
                  let date = formatter.date(from: operation.operationDate),
                  let amount = operation.validatedAmount else { return nil }
            return .init(
                fingerprint: operation.fingerprint,
                date: date,
                amount: amount,
                currency: operation.currency,
                type: kind == .income ? .income : .expense,
                categoryRaw: controller.categoryByFingerprint[operation.fingerprint] ?? "other",
                accountID: accountID,
                note: operation.description
            )
        }
        guard operations.count == controller.includedFingerprints.count else {
            controller.markApplyFailure()
            return
        }
        controller.markApplying()
        do {
            let result = try CashflowStatementApplyService(modelContext: modelContext).apply(operations)
            controller.markCompleted(result: result)
            viewModel.handle(.loadTransactions)
            showConfirmation = false
        } catch {
            controller.markApplyFailure()
        }
    }
}

private struct CashflowStatementConfirmationView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @ObservedObject var controller: CashflowStatementImportController
    let month: Date
    let apply: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var linksToAccount = false
    @State private var accountID = ""

    private var summary: CashflowStatementConfirmationSummary {
        .init(rows: controller.reviewRows)
    }

    private var selectableAccounts: [CashflowSelectableAccount] {
        CashflowStatementAccountSelectionPolicy.options(
            cards: viewModel.state.availableCards,
            newCoreAccounts: viewModel.newCoreAccountsForCashflowPicker(),
            statementCurrencies: Set(controller.reviewRows.filter(\.disposition.isIncluded).map(\.currency))
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Месяц") {
                    Label(month.formatted(.dateTime.month(.wide).year()), systemImage: "calendar")
                }
                Section("Предлагаемый импорт") {
                    LabeledContent("Будет импортировано", value: "\(summary.includedCount)")
                    LabeledContent("Исключено", value: "\(summary.excludedCount)")
                    if summary.reclassifiedCount > 0 {
                        LabeledContent("Преобразовано переводов", value: "\(summary.reclassifiedCount)")
                    }
                    ForEach(summary.totalsByCurrency.keys.sorted(), id: \.self) { currency in
                        LabeledContent(currency, value: summary.totalsByCurrency[currency] ?? 0, format: .currency(code: currency))
                    }
                }
                if let preview = controller.preview {
                    Section("Сверка исходной выписки") {
                        Label(preview.reconciliation.balanced ? "Баланс сходится" : "Есть расхождение", systemImage: preview.reconciliation.balanced ? "checkmark.seal" : "exclamationmark.triangle")
                        LabeledContent("Разница", value: preview.reconciliation.difference)
                    }
                }
                Section("Счёт") {
                    Toggle("Связать операции со счётом", isOn: $linksToAccount)
                    if linksToAccount {
                        if selectableAccounts.isEmpty {
                            Label("Нет активных счетов в валюте импортируемых операций", systemImage: "creditcard.trianglebadge.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Счёт", selection: $accountID) {
                                Text("Выберите счёт").tag("")
                                ForEach(selectableAccounts) { account in
                                    Text("\(account.pickerTitle) · \(account.currency)")
                                        .tag(account.cardID ?? "")
                                }
                            }
                        }
                    }
                    Label("Баланс счёта не изменится", systemImage: "shield.checkered")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Подтвердить импорт \(summary.includedCount) операций") {
                        apply(linksToAccount ? accountID : nil)
                    }
                    .disabled(
                        summary.includedCount == 0
                            || (linksToAccount && !CashflowStatementAccountSelectionPolicy.isValid(accountID, in: selectableAccounts))
                    )
                }
            }
            .navigationTitle("Подтверждение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .onAppear {
                viewModel.handle(.loadCards)
            }
            .onChange(of: selectableAccounts.map(\.id)) { _, _ in
                if !CashflowStatementAccountSelectionPolicy.isValid(accountID, in: selectableAccounts) {
                    accountID = ""
                }
            }
        }
    }
}
