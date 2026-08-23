//
//  StartupTrace.swift
//  millio
//
//  ВРЕМЕННАЯ диагностика двойного прохода UI на холодном старте.
//  Пишет в stdout (виден через `devicectl device process launch --console`).
//

import Foundation

enum StartupTrace {
    #if DEBUG
    private static let start = Date()
    private static let pid = ProcessInfo.processInfo.processIdentifier
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let dt = String(format: "%7.3f", Date().timeIntervalSince(start))
        print("STARTUP_TRACE [pid \(pid)] t+\(dt)s \(message())")
        fflush(stdout)
        #endif
    }
}
