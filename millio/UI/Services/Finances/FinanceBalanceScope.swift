//
//  FinanceBalanceScope.swift
//  millio
//
//  Created by Codex on 07.06.2026.
//

import Foundation

/// Declares why finance accounts are requested for a balance calculation.
/// Phase 0 introduces the contract only; filtering still stays in the existing call sites
/// until the follow-up phases migrate `FinanceDynamicsViewModel` to this enum.
enum FinanceBalanceScope {
    /// Active, user-visible accounts for live header, total, currency, and breakdown values.
    case currentVisible

    /// Accounts that existed at a specific historical point, including archived links for chart replay.
    case historicalAsOf(Date)

    /// Accounts needed to resolve the full historical period, including archived links that affect range bounds.
    case historicalInterval(DateInterval)

    /// Dashboard/overview sparkline snapshot scope, kept separate from the live header contract.
    case dashboardSnapshot

    /// Cashflow income/expense/asset-delta contribution scope.
    case cashflowContribution
}
