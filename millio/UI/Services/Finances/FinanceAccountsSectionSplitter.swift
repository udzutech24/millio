import Foundation

/// Разбивка списка групп «Счетов» на секции «Активы»/«Обязательства» (Гейт 5c.7.6.2).
///
/// Классификация — знак NET-тотала группы В ВАЛЮТЕ ШАПКИ (`FinanceViewModel.state
/// .groupTotalsPrimaryCurrency`, НЕ собственная `displayCurrency` группы — иначе подытоги секций не
/// сложились бы в тотал шапки на мультивалютных группах). Для смешанной группы (и актив, и
/// обязательство внутри одной `AccountGroup`) отдельного дробления НЕТ — вся группа целиком уходит в
/// секцию по знаку своего net-бейджа: это тот же знак, что пользователь уже видит на строке группы
/// (`FinanceGroupRow`), поэтому раздел не противоречит бейджу. Альтернатива «доминирующий kind»
/// отвергнута ментором: она может увести группу с ПОЛОЖИТЕЛЬНЫМ бейджем в «Обязательства» (если внутри
/// больше счетов-кредитов, чем депозитов, но депозит перекрывает долг по сумме) — это доказуемо более
/// запутанно для пользователя, чем знаковое правило.
enum FinanceAccountsSectionSplitter {
    struct Section: Equatable {
        let groupIDs: [String]
        let subtotal: Double
    }

    struct Split: Equatable {
        let assets: Section
        let liabilities: Section
        /// `true` — Ungrouped учтён в `assets`; `false` — в `liabilities`; `nil` — бакета Ungrouped нет
        /// (пуст) и подытоги секций его не касаются.
        let ungroupedInAssets: Bool?
    }

    /// - Parameters:
    ///   - orderedGroupIDs: id непустых групп в порядке отображения (order уже применён вызывающей
    ///     стороной — сплиттер сохраняет относительный порядок внутри каждой секции).
    ///   - totalsInPrimaryCurrency: тотал каждой группы в валюте шапки; отсутствие ключа = 0 (группа
    ///     без загруженного тотала — edge case первого рендера до фонового обновления).
    ///   - ungroupedTotal: тотал Ungrouped в валюте шапки; `nil` — бакета Ungrouped нет вовсе.
    static func split(
        orderedGroupIDs: [String],
        totalsInPrimaryCurrency: [String: Double],
        ungroupedTotal: Double?
    ) -> Split {
        var assetsIDs: [String] = []
        var liabilitiesIDs: [String] = []
        var assetsSubtotal: Double = 0
        var liabilitiesSubtotal: Double = 0

        for id in orderedGroupIDs {
            let total = totalsInPrimaryCurrency[id] ?? 0
            if total < 0 {
                liabilitiesIDs.append(id)
                liabilitiesSubtotal += total
            } else {
                assetsIDs.append(id)
                assetsSubtotal += total
            }
        }

        var ungroupedInAssets: Bool?
        if let ungroupedTotal {
            if ungroupedTotal < 0 {
                liabilitiesSubtotal += ungroupedTotal
                ungroupedInAssets = false
            } else {
                assetsSubtotal += ungroupedTotal
                ungroupedInAssets = true
            }
        }

        return Split(
            assets: Section(groupIDs: assetsIDs, subtotal: assetsSubtotal),
            liabilities: Section(groupIDs: liabilitiesIDs, subtotal: liabilitiesSubtotal),
            ungroupedInAssets: ungroupedInAssets
        )
    }
}
