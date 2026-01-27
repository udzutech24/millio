//
//  MonetaCurrency.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

/// Общий тип валюты для всех денежных сервисов (Финансы, Курсы, Кредиты и т.д.)
enum MonetaCurrency: String, Codable, CaseIterable, Identifiable {
    
    // MARK: - Основные мировые
    case USD // США
    case EUR // Еврозона
    case GBP // Великобритания
    case JPY // Япония
    case CHF // Швейцария
    case CAD // Канада
    case AUD // Австралия
    case NZD // Новая Зеландия
    
    // MARK: - СНГ
    case RUB // Россия
    case KZT // Казахстан
    case UAH // Украина
    case BYN // Беларусь
    case AMD // Армения
    case AZN // Азербайджан
    case GEL // Грузия
    case UZS // Узбекистан
    case KGS // Кыргызстан
    case TJS // Таджикистан
    case MDL // Молдова
    
    // MARK: - Азия
    case CNY // Китай
    case HKD // Гонконг
    case SGD // Сингапур
    case KRW // Южная Корея
    case INR // Индия
    case IDR // Индонезия
    case MYR // Малайзия
    case PHP // Филиппины
    case THB // Таиланд
    case VND // Вьетнам
    case LKR // Шри-Ланка
    case PKR // Пакистан
    case BDT // Бангладеш
    case NPR // Непал
    
    // MARK: - Ближний Восток
    case AED // ОАЭ
    case SAR // Саудовская Аравия
    case QAR // Катар
    case KWD // Кувейт
    case BHD // Бахрейн
    case OMR // Оман
    case ILS // Израиль
    case IRR // Иран
    case TRY // Турция
    
    // MARK: - Европа (вне EUR)
    case SEK // Швеция
    case NOK // Норвегия
    case DKK // Дания
    case ISK // Исландия
    case PLN // Польша
    case CZK // Чехия
    case HUF // Венгрия
    case RON // Румыния
    case BGN // Болгария
    case RSD // Сербия
    case ALL // Албания
    case MKD // Северная Македония
    
    // MARK: - Африка
    case ZAR // ЮАР
    case EGP // Египет
    case MAD // Марокко
    case TND // Тунис
    case NGN // Нигерия
    case KES // Кения
    case GHS // Гана
    
    // MARK: - Латинская Америка
    case BRL // Бразилия
    case MXN // Мексика
    case ARS // Аргентина
    case CLP // Чили
    case COP // Колумбия
    case PEN // Перу
    case UYU // Уругвай
    case BOB // Боливия
    case PYG // Парагвай
    case DOP // Доминикана
    
    // MARK: - Идентификатор
    var id: String { rawValue }
    
    // MARK: - Символ валюты
    var symbol: String {
        switch self {
        case .RUB: return "₽"
        case .USD: return "$"
        case .EUR: return "€"
        case .GBP: return "£"
        case .JPY: return "¥"
        case .CNY: return "¥"
        case .KRW: return "₩"
        case .TRY: return "₺"
        case .INR: return "₹"
        case .ILS: return "₪"
        case .THB: return "฿"
        case .VND: return "₫"
        case .ZAR: return "R"
        case .BRL: return "R$"
        case .UAH: return "₴"
        case .KZT: return "₸"
        case .PHP: return "₱"
        case .IDR: return "Rp"
        case .MYR: return "RM"
        case .PLN: return "zł"
        case .CZK: return "Kč"
        case .HUF: return "Ft"
        case .SEK, .NOK, .DKK: return "kr"
        default:
            return rawValue
        }
    }
    
    // MARK: - Валюта по умолчанию
    static var `default`: MonetaCurrency { .RUB }
}

