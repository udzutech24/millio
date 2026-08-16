//
//  CashflowHeroPresentation.swift
//  millio
//
//  Pure presentation policy for the primary Cashflow hero.
//


struct CashflowHeroPresentation: Equatable {
    let difference: Double
    let income: Double
    let expense: Double
}

enum CashflowHeroPresentationPolicy {
    /// The hero describes transaction cashflow only. Asset revaluation belongs to
    /// the balance summary below and must not be mixed into this difference.
    static func make(
        totalIncome: Double,
        contributedExpense: Double
    ) -> CashflowHeroPresentation {
        let expense = -abs(contributedExpense)
        return CashflowHeroPresentation(
            difference: totalIncome + expense,
            income: totalIncome,
            expense: expense
        )
    }
}
