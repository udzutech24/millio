//
//  LaunchRecoveryPolicy.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

struct LaunchRecoveryPolicy {
    struct Input {
        let lifecycle: AppLifecycleState
        let hasCompletedOnboarding: Bool
        let didLocalStoreExistBeforeLaunch: Bool
        /// `nil` — посчитать локальные модели не удалось. Это НЕ «данных нет»:
        /// неизвестное состояние трактуется как потенциально непустое (безопасная сторона).
        let localDataCount: Int?
        let latestBackupInfo: BackupInfo?
        /// Стор гостя (пользователь ещё не вошёл). Восстанавливать облачную копию в гостевой
        /// стор нельзя: после входа она уедет в reconciliation guest→user и удвоит данные.
        let isGuestScope: Bool

        init(
            lifecycle: AppLifecycleState,
            hasCompletedOnboarding: Bool,
            didLocalStoreExistBeforeLaunch: Bool,
            localDataCount: Int?,
            latestBackupInfo: BackupInfo?,
            isGuestScope: Bool = false
        ) {
            self.lifecycle = lifecycle
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.didLocalStoreExistBeforeLaunch = didLocalStoreExistBeforeLaunch
            self.localDataCount = localDataCount
            self.latestBackupInfo = latestBackupInfo
            self.isGuestScope = isGuestScope
        }
    }

    enum BlockReason: Equatable {
        /// Пользователь ещё не вошёл: launch-recovery ждёт своего scope, а не молчит.
        case guestScopeBeforeSignIn
        case lifecycleNotReady
        case existingLocalStore
        case localDataPresent
        case noBackupAvailable
    }

    /// Почему автоматическое (деструктивное) восстановление запрещено, хотя экран показать надо.
    enum ManualOnlyReason: Equatable {
        case localDataCountUnknown
    }

    enum Decision: Equatable {
        case presentRestore
        /// Показать RestoreView, но без авто-restore: решение о перезаписи принимает пользователь.
        case presentRestoreManualOnly(ManualOnlyReason)
        case skip(BlockReason)

        var shouldPresentRestore: Bool {
            switch self {
            case .presentRestore, .presentRestoreManualOnly:
                return true
            case .skip:
                return false
            }
        }

        /// Разрешён ли автоматический restore без подтверждения пользователя.
        var allowsAutomaticRestore: Bool {
            if case .presentRestore = self {
                return true
            }
            return false
        }

        /// Является ли исход окончательным для текущего поколения scope.
        /// Транзиентные причины (ещё не готов lifecycle, онбординг не пройден, лукап бэкапа
        /// не дал результата) не должны блокировать повторную попытку recovery (SR7).
        var locksLaunchRecovery: Bool {
            switch self {
            case .presentRestore, .presentRestoreManualOnly:
                return true
            case .skip(.existingLocalStore), .skip(.localDataPresent):
                return true
            case .skip(.lifecycleNotReady), .skip(.noBackupAvailable),
                 .skip(.guestScopeBeforeSignIn):
                return false
            }
        }
    }

    static func evaluate(_ input: Input) -> Decision {
        // Гостевой стор — не место для облачной копии пользователя: решение откладывается
        // до входа (исход транзиентный, повторная оценка после свопа scope обязательна).
        guard !input.isGuestScope else {
            return .skip(.guestScopeBeforeSignIn)
        }
        // S1 (решение владельца): после переустановки человек хочет вернуть данные, а не смотреть
        // онбординг — непройденный онбординг больше не блокирует recovery. Но точка входа у двух
        // состояний разная: у нового пользователя приложение стоит на .onboarding, у прошедшего —
        // на .ready. Любой другой lifecycle — ещё не наш момент (транзиентный skip).
        guard input.lifecycle == (input.hasCompletedOnboarding ? .ready : .onboarding) else {
            return .skip(.lifecycleNotReady)
        }
        // Счёт локальных моделей не удался: молча выходить нельзя — иначе пользователь уходит
        // в онбординг поверх восстановимого бэкапа. Показываем ручной сценарий,
        // деструктивный авто-restore запрещён.
        guard let localDataCount = input.localDataCount else {
            guard input.latestBackupInfo != nil else {
                return .skip(.noBackupAvailable)
            }
            return .presentRestoreManualOnly(.localDataCountUnknown)
        }
        // Normal relaunch: store existed and still contains user data — nothing to recover.
        // But if the store existed yet is now empty (e.g. SwiftData schema migration wiped it),
        // fall through so we can offer restore from the available backup.
        if input.didLocalStoreExistBeforeLaunch && localDataCount > 0 {
            return .skip(.existingLocalStore)
        }
        guard localDataCount == 0 else {
            return .skip(.localDataPresent)
        }
        guard input.latestBackupInfo != nil else {
            return .skip(.noBackupAvailable)
        }
        return .presentRestore
    }

    static func shouldPresentRestore(
        lifecycle: AppLifecycleState,
        hasCompletedOnboarding: Bool,
        didLocalStoreExistBeforeLaunch: Bool,
        localDataCount: Int?,
        latestBackupInfo: BackupInfo?,
        isGuestScope: Bool = false
    ) -> Bool {
        evaluate(
            Input(
                lifecycle: lifecycle,
                hasCompletedOnboarding: hasCompletedOnboarding,
                didLocalStoreExistBeforeLaunch: didLocalStoreExistBeforeLaunch,
                localDataCount: localDataCount,
                latestBackupInfo: latestBackupInfo,
                isGuestScope: isGuestScope
            )
        ).shouldPresentRestore
    }

    /// Куда уходит приложение после экрана восстановления.
    /// Восстановившийся пользователь получает свои данные и настройки — гнать его в онбординг
    /// незачем; отказавшийся новый пользователь обязан пройти онбординг, иначе после S1
    /// (recovery до онбординга) вводные экраны исчезли бы совсем.
    static func lifecycleAfterRestoreFlow(
        didRestore: Bool,
        hasCompletedOnboarding: Bool
    ) -> AppLifecycleState {
        if didRestore || hasCompletedOnboarding {
            return .ready
        }
        return .onboarding
    }
}
