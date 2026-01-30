//
//  AppLogger.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import OSLog

enum LogLevel {
    case debug
    case info
    case warning
    case error
}

struct AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "millio"
    
    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
    
    static func log(_ level: LogLevel, category: String, _ message: String) {
        let logger = logger(category: category)
        
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .private)")
        case .error:
            logger.error("\(message, privacy: .private)")
        }
    }
}
