import Foundation

open class Logger {
    public enum Level {
        case debug
        case verbose
        case info
        case warning
        case error
    }

    private struct WeakLogger {
        weak var logger: Logger?
    }

    private static var boundLoggers: [ObjectIdentifier: WeakLogger] = [:]
    private static var categorizedLoggers: [String: [WeakLogger]] = [:]
    private static var lock = SpinLock()

    public static var `default` = Logger(category: "DKGame", bind: true)

    public let category: String
    public let isBound: Bool    // available for broadcast

    public init(category: String, bind: Bool) {
        self.category = category
        self.isBound = bind

        let key = ObjectIdentifier(self)
        synchronizedBy(locking: Self.lock) {
            if bind { Self.boundLoggers[key] = WeakLogger(logger: self) }
            if Self.categorizedLoggers[self.category] == nil {
                Self.categorizedLoggers[self.category] = [WeakLogger(logger: self)]
            } else {
                Self.categorizedLoggers[self.category]!.append(WeakLogger(logger: self))
            }
        }
    }

    deinit {
        let key = ObjectIdentifier(self)
        synchronizedBy(locking: Self.lock) {
            var loggers = Self.categorizedLoggers[self.category]!
            loggers = loggers.compactMap {
                if $0.logger != nil { // weak-self should be nil.
                    return $0
                }
                return nil
            }
            if loggers.isEmpty {
                Self.categorizedLoggers[self.category] = nil
            } else {
                Self.categorizedLoggers[self.category] = loggers
            }
            Self.boundLoggers[key] = nil
        }
    }

    public static func categorized(_ category: String) -> [Logger] {
        return synchronizedBy(locking: Self.lock) {
            if let loggers = Self.categorizedLoggers[category] {
                return loggers.compactMap { $0.logger }
            }
            return []
        }
    }

    public func log(level: Level, _ mesg: String) {
        print("[\(self.category):\(level)] \(mesg)")
    }

    public static func broadcast(level: Level, _ mesg: String) {
        let loggers = synchronizedBy(locking: Self.lock) {
            Self.boundLoggers.values.compactMap { $0.logger }
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

