//
//  AppLifecycleState.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

enum AppLifecycleState: Equatable {
    case launching
    case onboarding
    case ready
    case restoring
    /// Автоматическое восстановление из последнего бекапа (после потери данных при обновлении).
    /// Показывает экран загрузки без участия пользователя; при ошибке переходит в .restoring.
    case autoRestoring
    case error(AppError)
}
