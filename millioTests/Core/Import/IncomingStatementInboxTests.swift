import Foundation
import Testing
import UniformTypeIdentifiers
@testable import millio

struct IncomingStatementInboxTests {
    @Test func policyAcceptsOnlyMatchingSupportedSignatures() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pdf = root.appendingPathComponent("statement.pdf")
        try Data("%PDF-1.7\n".utf8).write(to: pdf)
        #expect(try IncomingStatementFilePolicy.validate(url: pdf, declaredType: .pdf).kind == .pdf)

        let csv = root.appendingPathComponent("statement.csv")
        try Data("date,amount\n2026-08-01,1\n".utf8).write(to: csv)
        #expect(try IncomingStatementFilePolicy.validate(url: csv, declaredType: .commaSeparatedText).kind == .csv)

        let fakePDF = root.appendingPathComponent("fake.pdf")
        try Data("not a pdf".utf8).write(to: fakePDF)
        #expect(throws: IncomingStatementFileError.signatureMismatch) {
            try IncomingStatementFilePolicy.validate(url: fakePDF, declaredType: .pdf)
        }
    }

    @Test func policyRejectsDirectorySymlinkZeroAndTypeMismatch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: IncomingStatementFileError.notRegularFile) {
            try IncomingStatementFilePolicy.validate(url: root, declaredType: .pdf)
        }
        let empty = root.appendingPathComponent("empty.csv")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        #expect(throws: IncomingStatementFileError.empty) {
            try IncomingStatementFilePolicy.validate(url: empty, declaredType: .commaSeparatedText)
        }
        let original = root.appendingPathComponent("original.pdf")
        try Data("%PDF-1.7".utf8).write(to: original)
        let link = root.appendingPathComponent("linked.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        #expect(throws: IncomingStatementFileError.symbolicLink) {
            try IncomingStatementFilePolicy.validate(url: link, declaredType: .pdf)
        }
        #expect(throws: IncomingStatementFileError.unsupportedType) {
            try IncomingStatementFilePolicy.validate(url: original, declaredType: .commaSeparatedText)
        }
    }

    @Test func inboxDeduplicatesQueuesAndExpiresDeterministically() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var now = Date(timeIntervalSince1970: 100)
        let inbox = IncomingStatementInbox(directoryURL: root.appendingPathComponent("inbox"), now: { now })
        let firstSource = root.appendingPathComponent("first.csv")
        try Data("a,b\n1,2\n".utf8).write(to: firstSource)
        let first = try inbox.enqueue(sourceURL: firstSource, declaredType: .commaSeparatedText)
        let duplicate = try inbox.enqueue(sourceURL: firstSource, declaredType: .commaSeparatedText)
        #expect(first.id == duplicate.id)
        #expect(try inbox.queuedItems().count == 1)

        now.addTimeInterval(IncomingStatementInbox.retention + 1)
        try inbox.cleanupExpired()
        #expect(try inbox.queuedItems().isEmpty)
    }

    @Test @MainActor func coordinatorDoesNotDrainBeforeReadiness() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = IncomingStatementInbox(directoryURL: root.appendingPathComponent("inbox"))
        let source = root.appendingPathComponent("statement.csv")
        try Data("a,b\n1,2\n".utf8).write(to: source)
        _ = try inbox.enqueue(sourceURL: source, declaredType: .commaSeparatedText)
        let coordinator = IncomingStatementCoordinator(inbox: inbox)
        #expect(try coordinator.nextItem(readiness: .locked) == nil)
        #expect(try coordinator.nextItem(readiness: .storeUnavailable) == nil)
        #expect(try coordinator.nextItem(readiness: .modalBusy) == nil)
        #expect(try coordinator.nextItem(readiness: .ready) != nil)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
