import SwiftUI
import SwiftData

/// Экран «Архив» нового ядра event-sourcing (Фаза 5, AC7). Единственное место в UI, где вызывается
/// физическое удаление счёта (`modelContext.delete(Account)` — через `AccountsCoreService.physicallyDelete`,
/// см. grep-гейт в брифинге Фазы 5). Из основного UI «Удалить» — всегда архивация (см. `AccountDetailView`).
struct ArchivedAccountsView: View {
    let modelContext: ModelContext

    @State private var refreshToken = UUID()
    @State private var pendingPhysicalDeletion: Account?
    @State private var errorMessage: String?

    /// Совпадает с бейджем живой строки (`NewCoreAccountRow`) — архив отличается только приглушением.
    private static let badgeSize: CGFloat = 36
    private static let dimmedOpacity: Double = 0.55

    private var service: AccountsCoreService {
        AccountsCoreService(modelContext: modelContext)
    }

    private var archivedAccounts: [Account] {
        _ = refreshToken
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.archivedAt != nil && $0.deletedAt == nil }
        )
        let accounts = (try? modelContext.fetch(descriptor)) ?? []
        return accounts.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    /// Один fetch оформлений на весь список — как в `FinanceViewModel`, не по строке.
    private var appearances: [UUID: AccountAppearanceSnapshot] {
        _ = refreshToken
        return (try? AccountAppearanceStore(context: modelContext).loadSnapshots()) ?? [:]
    }

    var body: some View {
        ZStack {
            GradientBackground()

            if archivedAccounts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.s) {
                        Text(L("accounts_core.archive.notice"))
                            .font(.millioCalloutRegular)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.xs)

                        let appearances = appearances
                        ForEach(archivedAccounts, id: \.id) { account in
                            row(for: account, appearance: appearances[account.id])
                        }
                    }
                    .padding(AppSpacing.l)
                }
            }
        }
        .navigationTitle(L("accounts_core.archive.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L("accounts_core.archive.delete_forever_confirm.title"),
            isPresented: Binding(
                get: { pendingPhysicalDeletion != nil },
                set: { if !$0 { pendingPhysicalDeletion = nil } }
            )
        ) {
            Button(L("accounts_core.archive.action.delete_forever"), role: .destructive) {
                confirmPhysicalDeletion()
            }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {
                pendingPhysicalDeletion = nil
            }
        } message: {
            Text(pendingPhysicalDeletion.map(deleteForeverMessage) ?? "")
        }
        .alert(
            L("accounts_core.detail.error.title"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: "archivebox")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.textTertiary)
            Text(L("accounts_core.archive.empty"))
                .font(.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func row(for account: Account, appearance: AccountAppearanceSnapshot?) -> some View {
        // Оформление то же, что в живом списке, но обесцвеченное: закрытый счёт не должен
        // выглядеть активнее рабочих. Резолвер — общая фабрика, второго здесь не заводим.
        let details = CashflowAccountPickerDetailsFactory.details(
            for: account,
            appearance: appearance,
            balance: nil
        )
        return VStack(alignment: .leading, spacing: AppSpacing.s) {
            NavigationLink {
                AccountDetailView(account: account, modelContext: modelContext)
            } label: {
                HStack(spacing: AppSpacing.m) {
                    AccountIconBadgeView(
                        iconName: details.iconName,
                        iconColor: details.iconColorHex,
                        fallback: details.fallbackIconName,
                        size: Self.badgeSize
                    )
                    .saturation(0)
                    .opacity(Self.dimmedOpacity)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(account.name)
                            .font(.millioSubheadline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(closedSubtitle(for: account))
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                    Text(formattedBalanceAtClose(for: account))
                        .font(.millioSubheadline)
                        .foregroundStyle(AppColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: AppSpacing.s) {
                Button(L("accounts_core.archive.action.restore")) {
                    restore(account)
                }
                .font(.millioCalloutSemibold)
                .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button(L("accounts_core.archive.action.delete_forever")) {
                    pendingPhysicalDeletion = account
                }
                .font(.millioCalloutSemibold)
                .foregroundStyle(AppColors.error)
            }
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Действия

    private func restore(_ account: Account) {
        do {
            try service.restoreAccount(account)
            // Этот экран не хранит ссылку на FinanceViewModel — без события `state.coreAccounts`
            // не узнает о возврате счёта из архива до случайного несвязанного `loadGroups()`
            // (тот же канал, что `AccountDetailView.archiveAccount()`, см. комментарий там).
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            refreshToken = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmPhysicalDeletion() {
        guard let account = pendingPhysicalDeletion else { return }
        pendingPhysicalDeletion = nil
        do {
            // Мягкое удаление (Ф5/Q1): история графика сохраняется, счёт лишь помечается tombstone
            // и уходит из списка архива (предикат `deletedAt == nil` ниже). Событие всё равно нужно —
            // `state.coreAccounts` мог держать ссылку на этот @Model, обновляем снапшот VM.
            try service.softDelete(account)
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            refreshToken = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Текст с реальными числами (задача 2 брифинга Фазы 5)

    /// «Сотрётся N операций за M лет» — числа РЕАЛЬНЫЕ, не шаблонные (осознанное решение пользователя).
    private func deleteForeverMessage(for account: Account) -> String {
        let events = account.events ?? []
        let count = events.count
        let years = yearsOfHistory(events: events)
        return String(format: L("accounts_core.archive.delete_forever_confirm.message_format"), count, years)
    }

    private func yearsOfHistory(events: [AccountEvent]) -> Int {
        guard let earliest = events.map(\.date).min() else { return 0 }
        let components = Calendar.current.dateComponents([.year], from: earliest, to: Date())
        return max(0, components.year ?? 0)
    }

    private func closedSubtitle(for account: Account) -> String {
        let kindTitle = accountKindTitle(account.kind)
        guard let archivedAt = account.archivedAt else { return kindTitle }
        let dateString = archivedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(kindTitle) · \(String(format: L("accounts_core.archive.closed_on_format"), dateString))"
    }

    /// НЕ через `L("accounts_core.kind.\(kind.rawValue)")` — динамическая интерполяция внутри
    /// `String.LocalizationValue` ломает резолвинг ключа (Foundation трактует интерполированную
    /// часть как format-аргумент, а не как часть ключа каталога строк). Явный switch — безопасно.
    private func accountKindTitle(_ kind: AccountKind) -> String {
        switch kind {
        case .cash: return L("accounts_core.kind.cash")
        case .debitCard: return L("accounts_core.kind.debitCard")
        case .bankAccount: return L("accounts_core.kind.bankAccount")
        case .deposit: return L("accounts_core.kind.deposit")
        case .loan: return L("accounts_core.kind.loan")
        case .debt: return L("accounts_core.kind.debt")
        case .marketInvestment: return L("accounts_core.kind.marketInvestment")
        case .manualAsset: return L("accounts_core.kind.manualAsset")
        }
    }

    private func formattedBalanceAtClose(for account: Account) -> String {
        let closingDate = account.archivedAt ?? Date()
        // Ф1: баланс на закрытие — подтверждённый; прогноз, не наступивший до закрытия счёта,
        // деньгами так и не стал.
        let balance = AccountBalanceEngine.balanceAt(
            events: DepositConfirmedBalanceResolver.confirmedEvents(
                account.events ?? [], accountID: account.id, kind: account.kind
            ),
            kind: account.kind,
            on: closingDate,
            marketMeta: account.marketMeta
        )
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let amount = formatter.string(from: NSDecimalNumber(decimal: balance)) ?? "0"
        return "\(amount) \(account.currency)"
    }
}
