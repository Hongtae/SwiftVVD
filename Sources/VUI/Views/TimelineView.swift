//
//  File: TimelineView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol TimelineSchedule {
    typealias Mode = TimelineScheduleMode

    associatedtype Entries: Sequence where Entries.Element == Date

    func entries(from startDate: Date, mode: Mode) -> Entries
}

public enum TimelineScheduleMode: Sendable, Hashable {
    case normal
    case lowFrequency
}

public extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    static func periodic(
        from startDate: Date,
        by interval: TimeInterval
    ) -> PeriodicTimelineSchedule {
        .init(from: startDate, by: interval)
    }
}

public extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    static var everyMinute: EveryMinuteTimelineSchedule {
        .init()
    }
}

public extension TimelineSchedule {
    static func explicit<S>(_ dates: S) -> ExplicitTimelineSchedule<S>
    where Self == ExplicitTimelineSchedule<S>, S: Sequence, S.Element == Date {
        .init(dates)
    }
}

public struct PeriodicTimelineSchedule: TimelineSchedule, Sendable {
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        public typealias Element = Date
        public typealias Iterator = Entries

        var date: Date
        var interval: TimeInterval

        public mutating func next() -> Date? {
            let result = date
            date += interval
            return result
        }
    }

    var date: Date
    var interval: TimeInterval

    public init(from startDate: Date, by interval: TimeInterval) {
        self.date = startDate
        self.interval = interval
    }

    public func entries(
        from startDate: Date,
        mode: TimelineScheduleMode
    ) -> Entries {
        let firstDate: Date
        if startDate <= date || interval == 0 {
            firstDate = date
        } else {
            let elapsed = startDate.timeIntervalSince(date)
            firstDate = date.addingTimeInterval(floor(elapsed / interval) * interval)
        }
        return Entries(date: firstDate, interval: interval)
    }
}

public struct EveryMinuteTimelineSchedule: TimelineSchedule, Sendable {
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        public typealias Element = Date
        public typealias Iterator = Entries

        var nextDate: Date?

        public mutating func next() -> Date? {
            guard let date = nextDate else {
                return nil
            }
            nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: date)
            return date
        }
    }

    public init() {}

    public func entries(
        from startDate: Date,
        mode: TimelineScheduleMode
    ) -> Entries {
        let components = Calendar.current.dateComponents(
            [.era, .year, .month, .day, .hour, .minute],
            from: startDate
        )
        return Entries(nextDate: Calendar.current.date(from: components))
    }
}

public struct ExplicitTimelineSchedule<Entries>: TimelineSchedule
where Entries: Sequence, Entries.Element == Date {
    var entries: Entries

    public init(_ dates: Entries) {
        entries = dates
    }

    public func entries(
        from startDate: Date,
        mode: TimelineScheduleMode
    ) -> Entries {
        entries
    }
}

@available(*, unavailable)
extension ExplicitTimelineSchedule: Sendable {}

public struct AnimationTimelineSchedule: TimelineSchedule, Sendable {
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        public typealias Element = Date
        public typealias Iterator = Entries

        var date: Date
        var interval: Double?

        public mutating func next() -> Date? {
            guard let interval else {
                return nil
            }
            let result = date
            date += interval
            return result
        }
    }

    var minimumInterval: Double
    var paused: Bool

    public init(minimumInterval: Double? = nil, paused: Bool = false) {
        self.minimumInterval = minimumInterval ?? (1.0 / 120.0)
        self.paused = paused
    }

    public func entries(
        from start: Date,
        mode: TimelineScheduleMode
    ) -> Entries {
        Entries(
            date: start,
            interval: paused || mode == .lowFrequency ? nil : minimumInterval
        )
    }
}

public extension TimelineSchedule where Self == AnimationTimelineSchedule {
    static var animation: AnimationTimelineSchedule {
        .init()
    }

    static func animation(
        minimumInterval: Double? = nil,
        paused: Bool = false
    ) -> AnimationTimelineSchedule {
        .init(minimumInterval: minimumInterval, paused: paused)
    }
}

public struct TimelineView<Schedule, Content> where Schedule: TimelineSchedule {
    public struct Context {
        public enum Cadence: Comparable, Sendable, Hashable {
            case live
            case seconds
            case minutes

            public static func < (lhs: Self, rhs: Self) -> Bool {
                rank(lhs) < rank(rhs)
            }

            private static func rank(_ cadence: Self) -> UInt8 {
                switch cadence {
                case .live: 0
                case .seconds: 1
                case .minutes: 2
                }
            }
        }

        public let date: Date
        public let cadence: Cadence
    }

    typealias CanonicalContext = TimelineView<PeriodicTimelineSchedule, Never>.Context

    var schedule: Schedule
    var content: (CanonicalContext) -> Content

    init(
        _ schedule: Schedule,
        content: @escaping (Context) -> Content
    ) {
        self.schedule = schedule
        self.content = unsafeBitCast(
            content,
            to: ((CanonicalContext) -> Content).self
        )
    }
}

@available(*, unavailable)
extension TimelineView: Sendable {}

@available(*, unavailable)
extension TimelineView.Context: Sendable {}

public typealias TimelineViewDefaultContext =
    TimelineView<EveryMinuteTimelineSchedule, Never>.Context

struct ReferenceDateInput: ViewInput {
    static var defaultValue: WeakAttribute<Date?> { WeakAttribute() }
}

extension TimelineView: View where Content: View {
    public typealias Body = Never

    public init(
        _ schedule: Schedule,
        @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content
    ) {
        self.init(schedule) { (context: Context) -> Content in
            content(unsafeBitCast(context, to: TimelineViewDefaultContext.self))
        }
    }

    public static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        let content: Attribute<Content> = graph.makeStatefulRule(
            TimelineViewUpdateFilter(
                _view: view._attribute,
                _schedule: view[\.schedule]._attribute,
                _phase: inputs.base.phase,
                _time: inputs.base.time,
                _referenceDate: inputs[ReferenceDateInput.self],
                resetSeed: 0,
                iterator: nil,
                currentTime: -.infinity,
                nextTime: .infinity,
                cadence: .live
            )
        )
        return Content._makeView(
            view: _GraphValue(_attribute: content),
            inputs: inputs
        )
    }
}

extension TimelineView: PrimitiveView, UnaryView where Content: View {}

private struct TimelineViewUpdateFilter<Schedule, Content>: StatefulRule
where Schedule: TimelineSchedule, Content: View {
    typealias Value = Content
    typealias ViewType = TimelineView<Schedule, Content>

    var _view: Attribute<ViewType>
    var _schedule: Attribute<Schedule>
    var _phase: Attribute<Phase>
    var _time: Attribute<Time>
    var _referenceDate: WeakAttribute<Date?>
    var resetSeed: UInt32
    var iterator: Schedule.Entries.Iterator?
    var currentTime: Double
    var nextTime: Double
    var cadence: ViewType.Context.Cadence

    mutating func updateValue() {
        let phase = _phase.value
        let scheduleChanged =
            _AGGraph.currentStatefulInputChanged(_schedule.identifier)
            || _AGGraph.currentStatefulInputChanged(_view.identifier)
        if resetSeed != phase.resetSeed {
            resetSeed = phase.resetSeed
            iterator = nil
            currentTime = -.infinity
            nextTime = .infinity
        }

        let graphTime = _time.value
        let referenceDate = context[_referenceDate] ?? nil
        let now = referenceDate ?? Date()
        let nowTime = now.timeIntervalSinceReferenceDate

        if scheduleChanged || iterator == nil {
            iterator = _schedule.value
                .entries(from: now, mode: .normal)
                .makeIterator()
            currentTime = iterator?.next()?.timeIntervalSinceReferenceDate ?? nowTime
            nextTime = iterator?.next()?.timeIntervalSinceReferenceDate ?? .infinity
        } else {
            while nextTime.isFinite && nextTime <= nowTime {
                currentTime = nextTime
                guard let next = iterator?.next() else {
                    nextTime = .infinity
                    break
                }
                let candidate = next.timeIntervalSinceReferenceDate
                if candidate <= nextTime {
                    nextTime = candidate
                    break
                }
                nextTime = candidate
            }
        }

        if nextTime.isFinite,
           let viewGraph = GraphHost.currentHost as? ViewGraph {
            viewGraph.nextUpdate.views.at(
                graphTime + max(0, nextTime - nowTime)
            )
        }

        let context = ViewType.Context(
            date: Date(timeIntervalSinceReferenceDate: currentTime),
            cadence: cadence
        )
        let canonical = unsafeBitCast(
            context,
            to: ViewType.CanonicalContext.self
        )
        _AGGraph.setStatefulOutput(_view.value.content(canonical))
    }
}
