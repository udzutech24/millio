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
                #expect(false)
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
            #expect(false)
        } catch let error as SubscriptionError {
            switch error {
            case .trialAlreadyUsed:
                #expect(true)
            default:
                #expect(false)
            }
        } catch {
            #expect(false)
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
    
    @Test("scheduleDailyReminder добавляет ежедневный UNNotificationRequest при авторизации")
    func testScheduleDailyReminderAddsRequestWhenAuthorized() async {
        let fakeCenter = FakeNotificationCenter()
        let calendar = makeCalendarUTC()
        let manager = NotificationManager(notificationCenter: fakeCenter, now: { self.makeDate(day: 3) }, calendar: calendar)
        
        await manager.scheduleDailyReminder(enabled: true)
        
        #expect(fakeCenter.authorizationRequestCount == 1)
        #expect(fakeCenter.addedRequests.count == 1)
        #expect(fakeCenter.addedRequests.first?.identifier == "daily_reminder")
        
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
        
        let fake1 = FakeNotificationCenter()
        let manager1 = NotificationManager(notificationCenter: fake1, now: { self.makeDate(day: 1) }, calendar: calendar)
        await manager1.scheduleDailyReminder(enabled: true)
        let body1 = fake1.addedRequests.first?.content.body
        
        let fake2 = FakeNotificationCenter()
        let manager2 = NotificationManager(notificationCenter: fake2, now: { self.makeDate(day: 1) }, calendar: calendar)
        await manager2.scheduleDailyReminder(enabled: true)
        let body2 = fake2.addedRequests.first?.content.body
        
        #expect(body1 == body2)
        
        let fake3 = FakeNotificationCenter()
        let manager3 = NotificationManager(notificationCenter: fake3, now: { self.makeDate(day: 2) }, calendar: calendar)
        await manager3.scheduleDailyReminder(enabled: true)
        let body3 = fake3.addedRequests.first?.content.body
        
        #expect(body3 != body1)
    }
}
