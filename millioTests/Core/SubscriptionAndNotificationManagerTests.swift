import Foundation
import Testing
import UserNotifications
@testable import millio

@Suite(.serialized)
@MainActor
struct SubscriptionManagerTests {
    @Test("SubscriptionStatus rawValue round-trip")
    func testSubscriptionStatusRawValueRoundTrip() {
        let cases: [SubscriptionStatus] = [.notSubscribed, .trial, .subscribed, .expired]
        for value in cases {
            let decoded = SubscriptionStatus(rawValue: value.rawValue)
            switch (value, decoded) {
            case (.notSubscribed, .some(.notSubscribed)),
                 (.trial, .some(.trial)),
                 (.subscribed, .some(.subscribed)),
                 (.expired, .some(.expired)):
                #expect(true)
            default:
                #expect(Bool(false))
            }
        }
    }
    
    @Test("startTrial выставляет статус и сохраняет флаги в UserDefaults")
    func testStartTrialPersistsToUserDefaults() async throws {
        let suiteName = "SubscriptionManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let fixedNow = Date(timeIntervalSince1970: 10_000)
        let manager = SubscriptionManager(defaults: defaults, startTransactionListener: false, now: { fixedNow })
        
        try await manager.startTrial()
        
        #expect(manager.status.rawValue == SubscriptionStatus.trial.rawValue)
        #expect(manager.isTrialActive == true)
        #expect(defaults.bool(forKey: "trial_used") == true)
        #expect(defaults.object(forKey: "trial_start_date") as? Date == fixedNow)
        #expect(defaults.string(forKey: "subscription_status") == SubscriptionStatus.trial.rawValue)
    }
    
    @Test("startTrial бросает ошибку, если trial_used уже установлен")
    func testStartTrialFailsWhenAlreadyUsed() async throws {
        let suiteName = "SubscriptionManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        defaults.set(true, forKey: "trial_used")
        let manager = SubscriptionManager(defaults: defaults, startTransactionListener: false, now: { Date(timeIntervalSince1970: 10_000) })
        
        do {
            try await manager.startTrial()
            #expect(Bool(false))
        } catch let error as SubscriptionError {
            switch error {
            case .trialAlreadyUsed:
                #expect(true)
            default:
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
    }
    
    @Test("loadLocalStatus выставляет isTrialActive по trial_start_date")
    func testInitLoadsTrialActiveFromDefaults() {
        let suiteName = "SubscriptionManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let now = Date(timeIntervalSince1970: 10_000)
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        defaults.set(threeDaysAgo, forKey: "trial_start_date")
        
        let manager = SubscriptionManager(defaults: defaults, startTransactionListener: false, now: { now })
        
        #expect(manager.isTrialActive == true)
    }

    @Test("Отладочный премиум можно включать и выключать через менеджер")
    func testDebugPremiumCanBeToggled() {
        let suiteName = "SubscriptionManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 10_000)
        let manager = SubscriptionManager(defaults: defaults, startTransactionListener: false, now: { now })

        manager.grantDebugPremium()
        #expect(manager.status.rawValue == SubscriptionStatus.subscribed.rawValue)
        #expect(manager.expirationDate != nil)
        #expect(defaults.bool(forKey: "debug_premium_enabled") == true)
        #expect(manager.isDebugPremiumActive == true)

        manager.revokeDebugPremium()
        #expect(manager.status.rawValue == SubscriptionStatus.notSubscribed.rawValue)
        #expect(manager.expirationDate == nil)
        #expect(defaults.bool(forKey: "debug_premium_enabled") == false)
        #expect(manager.isDebugPremiumActive == false)
    }

    @Test("snapshot отражает debug override как отдельный источник доступа")
    func testSnapshotUsesDebugAccessSource() {
        let suiteName = "SubscriptionManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 10_000)
        let manager = SubscriptionManager(defaults: defaults, startTransactionListener: false, now: { now })

        manager.grantDebugPremium()

        #expect(manager.snapshot.hasDebugPremiumOverride == true)
        #expect(manager.snapshot.accessSource == .debug)
        #expect(manager.snapshot.isPro == true)
    }

    @Test("Trial можно форс-выключить через override и вернуть обратно, пока он не истек")
    func testTrialDisabledOverrideForcesTrialOff() async throws {
        let suiteName = "SubscriptionManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 10_000)
        let manager = SubscriptionManager(defaults: defaults, startTransactionListener: false, now: { now })

        try await manager.startTrial()
        #expect(manager.isTrialActive == true)
        #expect(manager.snapshot.accessSource == .trial)

        manager.setTrialDisabledOverride(true)
        #expect(manager.hasTrialDisabledOverride == true)
        #expect(manager.isTrialActive == false)
        #expect(manager.snapshot.accessSource == .free)

        manager.setTrialDisabledOverride(false)
        #expect(manager.hasTrialDisabledOverride == false)
        #expect(manager.isTrialActive == true)
        #expect(manager.snapshot.accessSource == .trial)
    }
}

final class FakeNotificationCenter: UserNotificationCenterProtocol {
    var authorizationGranted: Bool = true
    private(set) var authorizationRequestCount: Int = 0
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPending: [[String]] = []
    private(set) var removedDelivered: [[String]] = []
    
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequestCount += 1
        return authorizationGranted
    }
    
    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }
    
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPending.append(identifiers)
    }
    
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(identifiers)
    }
}

@Suite(.serialized)
@MainActor
struct NotificationManagerTests {
    private func makeCalendarUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    
    private func makeDate(year: Int = 2026, month: Int = 1, day: Int) -> Date {
        let calendar = makeCalendarUTC()
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        return calendar.date(from: components)!
    }

    @Test("AccountsCore deposit reminder schedules one day before maturity and cancels by namespace")
    func accountDepositMaturityReminderLifecycle() async throws {
        let center = FakeNotificationCenter()
        let accountID = UUID()
        let manager = NotificationManager(
            notificationCenter: center, now: { self.makeDate(day: 10) },
            calendar: makeCalendarUTC(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        let scheduled = await manager.scheduleAccountDepositMaturityReminder(
            accountID: accountID, accountName: "Deposit", maturityDate: makeDate(day: 20)
        )
        #expect(scheduled)
        let request = try #require(center.addedRequests.first)
        #expect(request.identifier == NotificationManager.accountDepositReminderIdentifier(accountID))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 19)
        #expect(trigger.dateComponents.hour == 9)
        manager.cancelAccountDepositMaturityReminder(accountID: accountID)
        #expect(center.removedPending.last == [NotificationManager.accountDepositReminderIdentifier(accountID)])
    }

    @Test("AccountsCore deposit reminder stays unscheduled after denial or past maturity")
    func accountDepositReminderDenialAndPastDate() async {
        let denied = FakeNotificationCenter(); denied.authorizationGranted = false
        let manager = NotificationManager(
            notificationCenter: denied, now: { self.makeDate(day: 10) }, calendar: makeCalendarUTC(),
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        #expect(await !manager.scheduleAccountDepositMaturityReminder(
            accountID: UUID(), accountName: "Deposit", maturityDate: makeDate(day: 20)
        ))
        #expect(await !manager.scheduleAccountDepositMaturityReminder(
            accountID: UUID(), accountName: "Deposit", maturityDate: makeDate(day: 9)
        ))
        #expect(denied.addedRequests.isEmpty)
    }

    @Test("Credit-card reminder reuses NotificationManager with an exact one-time trigger")
    func creditCardPaymentReminder() async throws {
        let center = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let accountID = UUID()
        var settings = CreditCardPaymentSettings()
        settings.mode = .exactDate
        settings.exactDate = makeDate(month: 2, day: 20)
        settings.reminderLead = .threeDays
        settings.reminderHour = 9
        settings.reminderMinute = 15
        let manager = NotificationManager(
            notificationCenter: center,
            now: { self.makeDate(month: 2, day: 1) },
            calendar: calendar,
            languageProvider: { .russian }
        )

        await manager.scheduleCreditCardPaymentReminder(
            accountID: accountID, cardName: "Card", settings: settings, graceDays: nil
        )

        let request = try #require(center.addedRequests.first)
        #expect(request.identifier == NotificationManager.creditCardReminderIdentifier(accountID: accountID))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats == false)
        #expect(trigger.dateComponents.day == 17)
        #expect(trigger.dateComponents.hour == 9)
        #expect(trigger.dateComponents.minute == 15)
    }
    
    @Test("scheduleDailyReminder добавляет ежедневный UNNotificationRequest при авторизации")
    func testScheduleDailyReminderAddsRequestWhenAuthorized() async {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { self.makeDate(day: 3) },
            calendar: calendar,
            languageProvider: { .russian }
        )
        
        await manager.scheduleDailyReminder(using: DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.expense],
            cadence: .daily,
            hour: 20,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: self.makeDate(day: 3),
            customText: ""
        ))
        
        #expect(fakeCenter.authorizationRequestCount == 1)
        #expect(fakeCenter.addedRequests.count == 1)
        #expect(fakeCenter.addedRequests.first?.identifier == DailyReminderSettings.notificationIdentifier(for: .expense))
        
        let request = fakeCenter.addedRequests.first!
        #expect(request.content.title == "millio")
        #expect(request.content.body.isEmpty == false)
        
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 20)
        #expect(trigger?.dateComponents.minute == 0)
    }
    
    @Test("Текст напоминания детерминирован по дню месяца")
    func testReminderMessageIsDeterministicByDay() async {
        let calendar = makeCalendarUTC()
        let settings = DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.expense],
            cadence: .daily,
            hour: 20,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: self.makeDate(day: 1),
            customText: ""
        )
        
        let fake1 = FakeNotificationCenter()
        let manager1 = NotificationManager(
            notificationCenter: fake1,
            now: { self.makeDate(day: 1) },
            calendar: calendar,
            languageProvider: { .russian }
        )
        await manager1.scheduleDailyReminder(using: settings)
        let body1 = fake1.addedRequests.first?.content.body
        
        let fake2 = FakeNotificationCenter()
        let manager2 = NotificationManager(
            notificationCenter: fake2,
            now: { self.makeDate(day: 1) },
            calendar: calendar,
            languageProvider: { .russian }
        )
        await manager2.scheduleDailyReminder(using: settings)
        let body2 = fake2.addedRequests.first?.content.body
        
        #expect(body1 == body2)
        
        let fake3 = FakeNotificationCenter()
        let manager3 = NotificationManager(
            notificationCenter: fake3,
            now: { self.makeDate(day: 2) },
            calendar: calendar,
            languageProvider: { .russian }
        )
        await manager3.scheduleDailyReminder(using: settings)
        let body3 = fake3.addedRequests.first?.content.body
        
        #expect(body3 != body1)
    }

    @Test("Ежемесячное напоминание использует день месяца и заданное время")
    func testMonthlyReminderUsesDayOfMonth() async {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { self.makeDate(day: 3) },
            calendar: calendar,
            languageProvider: { .english }
        )

        await manager.scheduleDailyReminder(using: DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.income],
            cadence: .monthly,
            hour: 9,
            minute: 15,
            dayOfMonth: 12,
            selectedDate: self.makeDate(day: 12),
            customText: ""
        ))

        let trigger = fakeCenter.addedRequests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.day == 12)
        #expect(trigger?.dateComponents.hour == 9)
        #expect(trigger?.dateComponents.minute == 15)
    }

    @Test("Разовое напоминание использует конкретную дату и не повторяется")
    func testOneTimeReminderUsesSpecificDate() async throws {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let targetDate = makeDate(month: 2, day: 7)
        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { self.makeDate(day: 3) },
            calendar: calendar,
            languageProvider: { .russian }
        )

        await manager.scheduleDailyReminder(using: DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.custom],
            cadence: .once,
            hour: 14,
            minute: 45,
            dayOfMonth: 1,
            selectedDate: targetDate,
            customText: "Внести расходы"
        ))

        let request = try #require(fakeCenter.addedRequests.first)
        let trigger = request.trigger as? UNCalendarNotificationTrigger

        #expect(trigger?.repeats == false)
        #expect(trigger?.dateComponents.year == 2026)
        #expect(trigger?.dateComponents.month == 2)
        #expect(trigger?.dateComponents.day == 7)
        #expect(trigger?.dateComponents.hour == 14)
        #expect(trigger?.dateComponents.minute == 45)
        #expect(request.content.body == "Внести расходы")
    }

    @Test("Текст напоминания использует английский язык приложения")
    func testReminderMessageUsesEnglishLanguage() async throws {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { self.makeDate(day: 1) },
            calendar: calendar,
            languageProvider: { .english }
        )

        await manager.scheduleDailyReminder(using: DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.expense],
            cadence: .daily,
            hour: 10,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: self.makeDate(day: 1),
            customText: ""
        ))

        let request = try #require(fakeCenter.addedRequests.first)
        let expectedBody = DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.expense],
            cadence: .daily,
            hour: 10,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: self.makeDate(day: 1),
            customText: ""
        ).notificationBody(
            for: .expense,
            language: .english,
            calendar: calendar,
            now: self.makeDate(day: 1)
        )
        #expect(request.content.body == expectedBody)
    }

    @Test("Текст напоминания использует русский язык приложения")
    func testReminderMessageUsesRussianLanguage() async throws {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { self.makeDate(day: 1) },
            calendar: calendar,
            languageProvider: { .russian }
        )

        await manager.scheduleDailyReminder(using: DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.income],
            cadence: .daily,
            hour: 10,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: self.makeDate(day: 1),
            customText: ""
        ))

        let request = try #require(fakeCenter.addedRequests.first)
        let expectedBody = DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.income],
            cadence: .daily,
            hour: 10,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: self.makeDate(day: 1),
            customText: ""
        ).notificationBody(
            for: .income,
            language: .russian,
            calendar: calendar,
            now: self.makeDate(day: 1)
        )
        #expect(request.content.body == expectedBody)
    }

    @Test("Можно включить несколько типов напоминаний одновременно")
    func testMultipleKindsScheduleMultipleRequests() async {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { self.makeDate(day: 1) },
            calendar: calendar,
            languageProvider: { .english }
        )

        await manager.scheduleDailyReminder(using: DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.expense, .custom],
            cadence: .daily,
            hour: 10,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: self.makeDate(day: 1),
            customText: "Custom ping"
        ))

        #expect(fakeCenter.addedRequests.count == 2)
        #expect(fakeCenter.addedRequests.map(\.identifier).contains(DailyReminderSettings.notificationIdentifier(for: .expense)))
        #expect(fakeCenter.addedRequests.map(\.identifier).contains(DailyReminderSettings.notificationIdentifier(for: .custom)))
    }

    @Test("Плановые cashflow напоминания ставятся для будущих одноразовых и регулярных операций")
    func testScheduleCashflowRemindersForPlannedAndRecurring() async throws {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let fixedNow = makeDate(month: 3, day: 10)
        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { fixedNow },
            calendar: calendar,
            languageProvider: { .russian },
            defaults: UserDefaults(suiteName: "NotificationManagerTests-\(UUID().uuidString)")!
        )

        let plannedExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: makeDate(month: 3, day: 12),
            cardID: nil
        )
        let recurringIncome = CashflowTransaction(
            transactionType: .income,
            amount: 200,
            currency: "RUB",
            transactionDate: makeDate(month: 2, day: 5),
            cardID: nil,
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-reminder"
        )
        let pastExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 50,
            currency: "RUB",
            transactionDate: makeDate(month: 3, day: 1),
            cardID: nil
        )

        await manager.scheduleCashflowScheduledReminders(for: [plannedExpense, recurringIncome, pastExpense])

        #expect(fakeCenter.addedRequests.count == 2)
        #expect(fakeCenter.addedRequests.allSatisfy { $0.identifier.contains("cashflow_scheduled_reminder") })
        let bodies = fakeCenter.addedRequests.map(\.content.body).joined(separator: " | ")
        #expect(bodies.contains("запланирован"))
    }

    @Test("Плановые cashflow напоминания используют выбранный язык приложения, включая zh-Hans")
    func testScheduleCashflowRemindersUseResolvedAppLanguage() async throws {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let fixedNow = makeDate(month: 3, day: 10)
        let suiteName = "NotificationManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotificationManager(
            notificationCenter: fakeCenter,
            now: { fixedNow },
            calendar: calendar,
            languageProvider: { .simplifiedChinese },
            defaults: defaults
        )

        let plannedExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "CNY",
            transactionDate: makeDate(month: 3, day: 12),
            cardID: nil
        )

        await manager.scheduleCashflowScheduledReminders(for: [plannedExpense])

        let request = try #require(fakeCenter.addedRequests.first)
        #expect(request.content.body.contains("提醒："))
        #expect(request.content.body.contains("支出"))
        #expect(!request.content.body.contains("Reminder:"))
        #expect(!request.content.body.contains("Напоминание:"))
    }
}
