//
//  AppleCalendarEventExport.swift
//  millio
//
//  EventKit boundary for one-way user-confirmed exports. The caller owns presentation and
//  persistence: this type never saves an event and never stores an external event identifier.
//

import EventKit
import Foundation

struct AppleCalendarEventExportPayload: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let notes: String?
    let startDate: Date
    let endDate: Date
    let timeZone: TimeZone

    static let eventDuration: TimeInterval = 15 * 60
}

enum AppleCalendarEventExportEligibility {
    /// Calendar export is intentionally limited to a future planner occurrence.
    /// A same-day cashflow is already due and must not create a misleading 09:00 event.
    static func isEligible(scheduledDate: Date, now: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: scheduledDate) > calendar.startOfDay(for: now)
    }
}

struct AppleCalendarEventExportPayloadBuilder {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makePayload(
        title: String,
        notes: String?,
        scheduledDate: Date,
        hour: Int = 9,
        minute: Int = 0
    ) -> AppleCalendarEventExportPayload? {
        guard let startDate = calendar.date(
            bySettingHour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: scheduledDate,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else {
            return nil
        }

        return AppleCalendarEventExportPayload(
            title: title,
            notes: normalizedNotes(notes),
            startDate: startDate,
            endDate: startDate.addingTimeInterval(AppleCalendarEventExportPayload.eventDuration),
            timeZone: calendar.timeZone
        )
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum AppleCalendarAuthorizationState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
}

@MainActor
protocol AppleCalendarEventStoreProtocol {
    var authorizationState: AppleCalendarAuthorizationState { get }
    func requestWriteOnlyAccess() async throws -> Bool
}

@MainActor
final class AppleCalendarEventStore: AppleCalendarEventStoreProtocol {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    var authorizationState: AppleCalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .writeOnly, .fullAccess, .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    func requestWriteOnlyAccess() async throws -> Bool {
        try await eventStore.requestWriteOnlyAccessToEvents()
    }

    /// Returns an unsaved event for `EKEventEditViewController`. Saving remains an explicit
    /// user action in the system editor, which is added in UI phase 2.
    func makeUnsavedEvent(from payload: AppleCalendarEventExportPayload) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.title = payload.title
        event.notes = payload.notes
        event.startDate = payload.startDate
        event.endDate = payload.endDate
        event.timeZone = payload.timeZone
        event.addAlarm(EKAlarm(relativeOffset: 0))
        return event
    }

    /// Kept internal to the app module so the SwiftUI adapter can present Apple's editor with
    /// the same store that created the event. It must never be used for silent saves.
    var eventStoreForEditor: EKEventStore { eventStore }
}

@MainActor
final class AppleCalendarEventExportAuthorizer {
    private let eventStore: any AppleCalendarEventStoreProtocol

    init(eventStore: any AppleCalendarEventStoreProtocol) {
        self.eventStore = eventStore
    }

    @MainActor
    convenience init() {
        self.init(eventStore: AppleCalendarEventStore())
    }

    func authorizeForExport() async -> AppleCalendarAuthorizationState {
        switch eventStore.authorizationState {
        case .granted, .denied, .restricted:
            return eventStore.authorizationState
        case .notDetermined:
            do {
                return try await eventStore.requestWriteOnlyAccess() ? .granted : .denied
            } catch {
                return .denied
            }
        }
    }
}
