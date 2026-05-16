import SwiftUI

enum AppAnimation {
    static let standard: Animation = .easeInOut(duration: 0.2)
    static let medium: Animation = .easeInOut(duration: 0.25)
    static let fast: Animation = .easeInOut(duration: 0.18)
    static let easeOut: Animation = .easeOut(duration: 0.2)
    static let spring: Animation = .spring(response: 0.3, dampingFraction: 0.8)
    static let springGentle: Animation = .spring(response: 0.42, dampingFraction: 0.88)
}
