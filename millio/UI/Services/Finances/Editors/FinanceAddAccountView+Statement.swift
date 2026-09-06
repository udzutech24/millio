import SwiftUI
import SwiftData
import PhotosUI

/// Импорт выписки: онбординг-блок и клиент импорта.
extension FinanceAddAccountView {
    @ViewBuilder
    var statementOnboardingSection: some View {
        if AccountStatementOnboardingPresentationPolicy.isEligible(
            option: selectedProductOption,
            cardType: cardData?.cardType
        ) {
            VStack(alignment: .leading, spacing: 10) {
                FinancesSectionHeader(title: localized("finances.statement.section", fallback: "Bank statement"))
                FinancesGlassCard {
                    Button {
                        presentStatementOnboarding()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localized("finances.statement.upload", fallback: "Upload statement"))
                                    .font(.system(size: 16, weight: .semibold))
                                Text(localized("finances.statement.upload_hint", fallback: "Create the account and import reviewed operations in one step"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }
            }
        }
    }

    var statementImportClient: any CashflowStatementImportClient {
        guard let diContainer else { return UnavailableCashflowStatementImportClient() }
        return diContainer.apiClientFactory.makeCashflowStatementImportClient(authService: diContainer.authService)
    }

    func presentStatementOnboarding() {
        guard validateEntitlementsForSave(),
              let kind = newCoreMoneyKindForCurrentSelection,
              let command = try? moneyCreateCommand(kind: kind) else { return }
        statementDraft = AccountStatementCreateDraft(createTemplate: command)
        showStatementOnboarding = true
    }

    func invalidateStatementDraft() {
        statementDraft = nil
        showStatementOnboarding = false
    }
}
