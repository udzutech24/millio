//
//  FinanceAddAccountInvestmentPreset.swift
//  millio
//

import Foundation

enum FinanceAddAccountInvestmentPreset {
    case account
    /// Наличные (Ф2): та же денежная форма, что у банковского счёта, но продукт `.cash` —
    /// без реквизитов карты (банк/last4/овердрафт), их у денег в кошельке не существует.
    case cash
    case deposit
    case asset
    case category
}
