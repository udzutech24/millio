//
//  AppliedPlannedNoticeAppearancePlan.swift
//  millio
//
//  Чем сопровождается появление сводки: текстура шапки и вибрация.
//  Фаза 4 плана plans/2026-09-05__planned-operations-applied-notice.md.
//
//  Вынесено из вью по образцу LaunchSplashHapticsPlan: правило «Reduce Motion — без эффекта и без
//  вибрации» иначе проверялось бы только глазами на устройстве.
//

import Foundation

/// Оформление появления сводки применённых плановых операций.
struct AppliedPlannedNoticeAppearancePlan: Equatable {

    /// Тактильный отклик в момент появления. Одно значение — намеренно: сводка сообщает факт,
    /// а не результат действия пользователя, поэтому ей не нужна лестница событий как сплэшу.
    enum Haptic: Equatable {
        case softImpact
    }

    /// Дизеринг-градиент в шапке.
    let isDitherEnabled: Bool

    /// `nil` — не вибрировать.
    let haptic: Haptic?

    /// Reduce Motion выключает и текстуру, и вибрацию: настройка означает «поменьше движения от
    /// интерфейса», а дизеринг с проявлением — как раз движение, ради которого лист и трясёт.
    static func make(reduceMotion: Bool) -> AppliedPlannedNoticeAppearancePlan {
        reduceMotion
            ? AppliedPlannedNoticeAppearancePlan(isDitherEnabled: false, haptic: nil)
            : AppliedPlannedNoticeAppearancePlan(isDitherEnabled: true, haptic: .softImpact)
    }
}
