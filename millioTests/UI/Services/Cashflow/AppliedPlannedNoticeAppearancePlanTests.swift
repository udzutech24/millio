//
//  AppliedPlannedNoticeAppearancePlanTests.swift
//  millioTests
//
//  Гейт фазы 4: Reduce Motion выключает дизеринг-эффект и вибрацию, обычный режим — включает.
//  Проверяется план, а не рендер: шейдер и хаптика на симуляторе не наблюдаемы,
//  а решение «играть или нет» — обычная чистая функция.
//

import Foundation
import Testing
@testable import millio

@Suite("AppliedPlannedNoticeAppearancePlan — появление сводки")
struct AppliedPlannedNoticeAppearancePlanTests {

    @Test("Обычный режим: дизеринг включён, вибрация одна и мягкая")
    func defaultModePlaysEffectAndHaptic() {
        let plan = AppliedPlannedNoticeAppearancePlan.make(reduceMotion: false)

        #expect(plan.isDitherEnabled)
        #expect(plan.haptic == .softImpact)
    }

    @Test("Reduce Motion выключает и эффект, и вибрацию")
    func reduceMotionDisablesEffectAndHaptic() {
        let plan = AppliedPlannedNoticeAppearancePlan.make(reduceMotion: true)

        #expect(plan.isDitherEnabled == false)
        #expect(plan.haptic == nil)
    }

    /// Регрессия на половинчатую реализацию: убрать текстуру, но оставить вибрацию (или наоборот)
    /// — это нарушение настройки, которое на глаз в симуляторе не видно вовсе.
    @Test("Настройка гасит обе части сразу, а не одну из них")
    func reduceMotionSwitchesBothPartsTogether() {
        let plain = AppliedPlannedNoticeAppearancePlan.make(reduceMotion: true)
        let full = AppliedPlannedNoticeAppearancePlan.make(reduceMotion: false)

        #expect(plain == AppliedPlannedNoticeAppearancePlan(isDitherEnabled: false, haptic: nil))
        #expect(full == AppliedPlannedNoticeAppearancePlan(isDitherEnabled: true, haptic: .softImpact))
        #expect(plain != full)
    }
}
