import Foundation

enum DailySnapshotState: String, Codable, CaseIterable {
    case open
    case pendingFx
    case closed
    case fallbackClosed

    var isFullyClosed: Bool {
        self == .closed || self == .fallbackClosed
    }
}

