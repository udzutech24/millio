//
//  RestoreDiagnosticsLocalizationTests.swift
//  millioTests
//
//  R4: пользователь должен видеть, ЧТО именно пошло не так, и на своём языке.
//

import Foundation
import Testing
@testable import millio

struct RestoreDiagnosticsLocalizationTests {
    private static let requiredLanguages = ["ru", "en", "zh-Hans"]

    // MARK: - Ключи в каталоге

    @Test("Все причины провала восстановления переведены в каталоге")
    func testRestoreFailureCodesAreLocalized() throws {
        let codes: [RestoreFailureCode] = [
            .backupNotFound, .allCandidatesInvalid, .passphraseRequired, .passphraseNeededForDecrypt,
            .passphraseDecryptFailed, .keychainUnavailable, .keychainKeyMissingOnDevice,
            .decryptFailed, .preRestoreSnapshotFailed, .rollbackFailed
        ]
        let strings = try Self.xcstringsStrings()

        for code in codes {
            let key = code.localizationKey
            let hasCatalogEntry = Self.hasTranslations(for: key, in: strings)
            #expect(
                hasCatalogEntry || BackupL10n.hasInlineTranslation(for: key),
                "Нет перевода для ключа \(key)"
            )
            #expect(code.message.isEmpty == false)
        }
    }

    @Test("Все причины отказа лукапа переведены в каталоге")
    func testLookupFailureReasonsAreLocalized() throws {
        let strings = try Self.xcstringsStrings()

        for reason in [BackupLookupFailureReason.iCloudUnavailable, .network, .serviceBusy, .unknown] {
            let key = reason.localizationKey
            #expect(
                Self.hasTranslations(for: key, in: strings) || BackupL10n.hasInlineTranslation(for: key),
                "Нет перевода для ключа \(key)"
            )
        }
    }

    @Test("Строки состояний поиска бэкапа переведены в каталоге")
    func testLookupStateKeysAreLocalized() throws {
        let keys = [
            "backup.restore.lookup.failed.status",
            "backup.restore.lookup.failed.title",
            "backup.restore.lookup.timedout.title",
            "backup.restore.lookup.timedout.message",
            "backup.restore.empty.message.not_found",
            "backup.restore.empty.message.icloud_unavailable",
            "backup.restore.action.retry"
        ]
        let strings = try Self.xcstringsStrings()

        for key in keys {
            #expect(
                Self.hasTranslations(for: key, in: strings) || BackupL10n.hasInlineTranslation(for: key),
                "Нет перевода для ключа \(key)"
            )
        }
    }

    // MARK: - Различимость исходов на экране

    @Test("«Копий нет», «поиск не удался» и «таймаут» — разные экраны")
    func testLookupOutcomesProduceDistinctPresentations() {
        let empty = BackupExperiencePresenter.restoreLookupPresentation(outcome: .empty, isICloudAvailable: true)
        let failed = BackupExperiencePresenter.restoreLookupPresentation(outcome: .failed(.network), isICloudAvailable: true)
        let timedOut = BackupExperiencePresenter.restoreLookupPresentation(outcome: .timedOut, isICloudAvailable: true)

        #expect(empty != failed)
        #expect(failed != timedOut)
        #expect(empty.title != failed.title)
        #expect(empty.message != failed.message)
        #expect(failed.message != timedOut.message)
    }

    @Test("Повтор предлагается на всех исходах без версии, включая ошибку и таймаут")
    func testRetryIsOfferedOnEveryUnresolvedOutcome() {
        for outcome in [BackupLookupOutcome.empty, .failed(.iCloudUnavailable), .timedOut] {
            let presentation = BackupExperiencePresenter.restoreLookupPresentation(
                outcome: outcome,
                isICloudAvailable: false
            )
            #expect(presentation.showsRetry)
        }
    }

    @Test("Причина отказа облака попадает в текст, а не подменяется на «копий нет»")
    func testFailureReasonReachesUser() {
        let notFoundMessage = BackupExperiencePresenter
            .restoreLookupPresentation(outcome: .empty, isICloudAvailable: true).message

        for reason in [BackupLookupFailureReason.iCloudUnavailable, .network, .serviceBusy, .unknown] {
            let message = BackupExperiencePresenter
                .restoreLookupPresentation(outcome: .failed(reason), isICloudAvailable: true).message
            #expect(message == reason.userMessage)
            #expect(message != notFoundMessage)
        }
    }

    // MARK: - Тексты ошибок восстановления

    @Test("Граничные случаи восстановления дают разные пользовательские тексты")
    func testBoundaryErrorsHaveDistinctMessages() {
        let corrupted = RestoreErrorPresenter.userMessage(for: AppError.backupCorrupted)
        let incompatible = RestoreErrorPresenter.userMessage(for: AppError.incompatibleSchemaVersion)
        let icloud = RestoreErrorPresenter.userMessage(for: AppError.iCloudUnavailable)
        let generic = RestoreErrorPresenter.userMessage(for: AppError.securityFailed("keychain"))

        #expect(Set([corrupted, incompatible, icloud, generic]).count == 4)
        // Техническая деталь из securityFailed не должна утекать на экран.
        #expect(generic.contains("keychain") == false)
    }

    @Test("Уже локализованное сообщение не обрастает техническим префиксом")
    func testLocalizedMessagePassesThroughWithoutPrefix() {
        let message = RestoreFailureCode.passphraseDecryptFailed.message

        let presented = RestoreErrorPresenter.userMessage(for: RestoreFailureCode.passphraseDecryptFailed.appError)

        #expect(presented == message)
        #expect(presented.hasPrefix("Restore failed:") == false)
    }

    @Test("Провал отката и провал проверки доходят до пользователя своими текстами")
    func testRollbackAndVerificationMessages() {
        let rollback = RestoreRollbackFailure(underlyingDescription: "sqlite error 11")
        let verification = RestoreVerificationFailure.emptyBackup

        let rollbackMessage = RestoreErrorPresenter.userMessage(for: rollback as Error)
        let verificationMessage = RestoreErrorPresenter.userMessage(for: verification as Error)

        #expect(rollbackMessage == rollback.errorDescription)
        #expect(rollbackMessage.contains("sqlite") == false)
        #expect(verificationMessage == verification.userMessage)
        #expect(rollbackMessage != verificationMessage)
    }

    // MARK: - Helpers

    private static func hasTranslations(for key: String, in strings: [String: Any]) -> Bool {
        guard
            let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any]
        else {
            return false
        }
        return requiredLanguages.allSatisfy { localizations[$0] != nil }
    }

    private static func xcstringsStrings() throws -> [String: Any] {
        let fileURL = try sourceURL(for: "millio/Localizable.xcstrings")
        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        let json = try #require(object as? [String: Any])
        return try #require(json["strings"] as? [String: Any])
    }

    private static func sourceURL(for relativePath: String) throws -> URL {
        let fileManager = FileManager.default
        var baseURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        for _ in 0..<8 {
            let candidate = baseURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            baseURL.deleteLastPathComponent()
        }

        throw NSError(
            domain: "RestoreDiagnosticsLocalizationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate source file: \(relativePath)"]
        )
    }
}
