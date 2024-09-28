//
//  File: Logger.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

open class Logger: @unchecked Sendable {
    public enum Level {
        case debug
        case verbose
        case info
        case warning
        case error
    }

    private struct SharedLoggers {
        var boundLoggers: [ObjectIdentifier: WeakObject<Logger>] = [:]
        var categorizedLoggers: [String: [WeakObject<Logger>]] = [:]
    }
    private static let sharedLoggers = Mutex<SharedLoggers>(SharedLoggers())

    public static let `default` = Logger(category: "VVD", bind: true)

    public let category: String
    public let isBound: Bool    // available for broadcast

    public init(category: String, bind: Bool) {
        self.category = category
        self.isBound = bind

        let key = ObjectIdentifier(self)
        Logger.sharedLoggers.withLock {
            if bind {
                $0.boundLoggers[key] = WeakObject(self)
            }
            if $0.categorizedLoggers[self.category] == nil {
                $0.categorizedLoggers[self.category] = [WeakObject(self)]
            } else {
                $0.categorizedLoggers[self.category]!.append(WeakObject(self))
            }
        }
    }

    deinit {
        let key = ObjectIdentifier(self)
        Logger.sharedLoggers.withLock {
            var loggers = $0.categorizedLoggers[self.category]!
            loggers = loggers.compactMap {
                if $0.value != nil {   // weak-self should be nil.
                    return $0
                }
                return nil
            }
            if loggers.isEmpty {
                $0.categorizedLoggers[self.category] = nil
            } else {
                $0.categorizedLoggers[self.category] = loggers
            }
            $0.boundLoggers[key] = nil
        }
    }

    public static func categorized(_ category: String) -> [Logger] {
        Logger.sharedLoggers.withLock {
            if let loggers = $0.categorizedLoggers[category] {
                return loggers.compactMap(\.value)
            }
            return []
        }
    }

    public func log(level: Level, _ mesg: String) {
        let tid = String(format: "%X", Platform.currentThreadID())
        print("[\(self.category):\(level):\(tid)] \(mesg)")
    }

    public static func broadcast(level: Level, _ mesg: String) {
        let loggers = Logger.sharedLoggers.withLock {
            $0.boundLoggers.values.compactMap(\.value)
        }
        loggers.forEach { $0.log(level: level, mesg) }
    }
}

public struct Log {
    public typealias Level = Logger.Level

    public static func log(category: String, level: Level, _ mesg: String) {
        Logger.categorized(category).forEach { $0.log(level: level, mesg) }
    }

    public static func log(level: Level, _ mesg: String) {
        _ = Logger.default
        Logger.broadcast(level: level, mesg)
    }

    public static func debug(_ mesg: String)    { log(level: .debug, mesg) }
    public static func verbose(_ mesg: String)  { log(level: .verbose, mesg) }
    public static func info(_ mesg: String)     { log(level: .info, mesg) }
    public static func warning(_ mesg: String)  { log(level: .warning, mesg) }
    public static func error(_ mesg: String)    { log(level: .error, mesg) }

    public static let warn = warning
    public static let err = error
}
