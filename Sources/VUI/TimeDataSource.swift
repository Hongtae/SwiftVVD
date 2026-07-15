//
//  File: TimeDataSource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private enum _TimeDataSourceIdentity: Hashable {
    case currentDate
    case durationOffset(Date)
    case dateRangeStarting(Date)
    case dateRangeEnding(Date)
}

final class _TimeDataSourceBox<Value>: @unchecked Sendable {
    let identity: AnyHashable
    private let valueProvider: (Date) -> Value
    private let dateProvider: (Value) -> Date?

    init(
        identity: AnyHashable,
        value: @escaping (Date) -> Value,
        date: @escaping (Value) -> Date?
    ) {
        self.identity = identity
        self.valueProvider = value
        self.dateProvider = date
    }

    func value(for date: Date) -> Value {
        valueProvider(date)
    }

    func date(for value: Value) -> Date? {
        dateProvider(value)
    }
}

public struct TimeDataSource<Value> {
    let box: _TimeDataSourceBox<Value>

    init(box: _TimeDataSourceBox<Value>) {
        self.box = box
    }
}

extension TimeDataSource: Sendable where Value: Sendable {}

extension TimeDataSource where Value == Date {
    public static var currentDate: TimeDataSource<Date> {
        TimeDataSource<Date>(
            box: _TimeDataSourceBox(
                identity: _TimeDataSourceIdentity.currentDate,
                value: { $0 },
                date: { $0 }
            )
        )
    }
}

extension TimeDataSource where Value == Duration {
    public static func durationOffset(to date: Date) -> TimeDataSource<Duration> {
        TimeDataSource<Duration>(
            box: _TimeDataSourceBox(
                identity: _TimeDataSourceIdentity.durationOffset(date),
                value: { currentDate in
                    .seconds(currentDate.timeIntervalSince(date))
                },
                date: { duration in
                    date.addingTimeInterval(_timeInterval(duration))
                }
            )
        )
    }
}

extension TimeDataSource where Value == Range<Date> {
    public static func dateRange(startingAt date: Date) -> TimeDataSource<Range<Date>> {
        TimeDataSource<Range<Date>>(
            box: _TimeDataSourceBox(
                identity: _TimeDataSourceIdentity.dateRangeStarting(date),
                value: { currentDate in
                    date..<max(date, currentDate)
                },
                date: { range in
                    range.upperBound
                }
            )
        )
    }

    public static func dateRange(endingAt date: Date) -> TimeDataSource<Range<Date>> {
        TimeDataSource<Range<Date>>(
            box: _TimeDataSourceBox(
                identity: _TimeDataSourceIdentity.dateRangeEnding(date),
                value: { currentDate in
                    min(currentDate, date)..<date
                },
                date: { range in
                    range.lowerBound
                }
            )
        )
    }
}

private func _timeInterval(_ duration: Duration) -> TimeInterval {
    let components = duration.components
    return TimeInterval(components.seconds) +
        TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
}
