import Foundation
import SwiftData

enum CashflowMonthClosureEventKind: String, Codable {
    case close
    case reopen
}

@Model
final class CashflowMonthClosureEvent: Persistable {
    var eventID: String = UUID().uuidString
    var monthStart: Date = Date()
    var kindRaw: String = CashflowMonthClosureEventKind.close.rawValue
    var occurredAt: Date = Date()
    var evidenceJSON: String?

    var kind: CashflowMonthClosureEventKind {
        get { CashflowMonthClosureEventKind(rawValue: kindRaw) ?? .close }
        set { kindRaw = newValue.rawValue }
    }

    init(eventID: String = UUID().uuidString, monthStart: Date, kind: CashflowMonthClosureEventKind, occurredAt: Date, evidenceJSON: String? = nil) {
        self.eventID = eventID
        self.monthStart = monthStart
        self.kindRaw = kind.rawValue
        self.occurredAt = occurredAt
        self.evidenceJSON = evidenceJSON
    }

    func export() throws -> Data {
        var dictionary: [String: Any] = [
            "type": "CashflowMonthClosureEvent",
            "eventID": eventID,
            "monthStart": monthStart.timeIntervalSince1970,
            "kindRaw": kindRaw,
            "occurredAt": occurredAt.timeIntervalSince1970
        ]
        if let evidenceJSON { dictionary["evidenceJSON"] = evidenceJSON }
        return try JSONSerialization.data(withJSONObject: dictionary)
    }

    static func `import`(_ data: Data) throws {
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dictionary["eventID"] as? String != nil,
              dictionary["monthStart"] as? TimeInterval != nil,
              dictionary["kindRaw"] as? String != nil,
              dictionary["occurredAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}

enum CashflowMonthMutation: String {
    case create, edit, delete, manualBulk, statementApply, scheduledApply
}

enum CashflowMonthMutationPolicyError: Error, Equatable {
    case closedMonth
}

@MainActor
struct CashflowMonthMutationPolicy {
    let modelContext: ModelContext
    var calendar: Calendar = .autoupdatingCurrent

    func isClosed(_ date: Date) -> Bool {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return false }
        let descriptor = FetchDescriptor<CashflowMonthClosureEvent>(
            predicate: #Predicate { $0.monthStart >= interval.start && $0.monthStart < interval.end },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor).first?.kind) == .close
    }

    func validate(_ mutation: CashflowMonthMutation, date: Date) throws {
        if isClosed(date) { throw CashflowMonthMutationPolicyError.closedMonth }
    }
}

struct CashflowMonthReadinessInput {
    let month: Date
    let now: Date
    let unresolvedImportRows: Int
    let duplicateRows: Int
    let uncategorizedRows: Int
    let reconciliationPassed: Bool?
    let accountAndMonthMatch: Bool
    let pendingScheduledWrites: Int
}

struct CashflowMonthReadiness: Equatable {
    let blockers: [String]
    let warnings: [String]
    var canClose: Bool { blockers.isEmpty }
}

enum CashflowMonthReadinessCalculator {
    static func calculate(_ input: CashflowMonthReadinessInput, calendar: Calendar = .autoupdatingCurrent) -> CashflowMonthReadiness {
        var blockers: [String] = []
        var warnings: [String] = []
        guard let month = calendar.dateInterval(of: .month, for: input.month),
              let current = calendar.dateInterval(of: .month, for: input.now),
              month.start < current.start else {
            return CashflowMonthReadiness(blockers: ["month_not_completed"], warnings: [])
        }
        if input.unresolvedImportRows > 0 { blockers.append("unresolved_import_rows") }
        if input.duplicateRows > 0 { blockers.append("duplicate_rows") }
        if input.uncategorizedRows > 0 { blockers.append("uncategorized_rows") }
        if input.reconciliationPassed == false { blockers.append("reconciliation_failed") }
        if !input.accountAndMonthMatch { blockers.append("account_month_mismatch") }
        if input.pendingScheduledWrites > 0 { warnings.append("pending_scheduled_writes") }
        return CashflowMonthReadiness(blockers: blockers, warnings: warnings)
    }
}

@MainActor
final class CashflowMonthClosureService {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let now: () -> Date

    init(modelContext: ModelContext, calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = Date.init) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
    }

    func close(month: Date, readiness: CashflowMonthReadiness, evidenceJSON: String? = nil) throws {
        guard readiness.canClose else { throw CashflowMonthClosureServiceError.notReady }
        guard !CashflowMonthMutationPolicy(modelContext: modelContext, calendar: calendar).isClosed(month) else { return }
        try append(kind: .close, month: month, evidenceJSON: evidenceJSON)
    }

    func reopen(month: Date) throws {
        guard CashflowMonthMutationPolicy(modelContext: modelContext, calendar: calendar).isClosed(month) else { return }
        try append(kind: .reopen, month: month, evidenceJSON: nil)
    }

    private func append(kind: CashflowMonthClosureEventKind, month: Date, evidenceJSON: String?) throws {
        guard let monthStart = calendar.dateInterval(of: .month, for: month)?.start else {
            throw CashflowMonthClosureServiceError.invalidMonth
        }
        modelContext.insert(CashflowMonthClosureEvent(monthStart: monthStart, kind: kind, occurredAt: now(), evidenceJSON: evidenceJSON))
        try modelContext.save()
    }
}

enum CashflowMonthClosureServiceError: Error { case notReady, invalidMonth }
