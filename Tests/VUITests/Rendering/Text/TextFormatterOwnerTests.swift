import Foundation
import XCTest
@testable import VUI

// ASSERTIONS textFormatterPublic27Observed

final class TextFormatterOwnerTests: XCTestCase {
    private var previousContext: (any AppContext)?
    private var sceneResources = SceneResources()

    override func setUp() {
        previousContext = appContext
        appContext = StyleTestAppContext()
        sceneResources = SceneResources()
    }

    override func tearDown() {
        appContext = previousContext
        previousContext = nil
    }

    func testNSObjectFormattingIsDeferredAndNilSkipsTheRun() throws {
        let subject = MutableFormatterSubject("initial")
        let formatter = RecordingTextFormatter(prefix: "object-a")
        let text = Text(subject, formatter: formatter)
        XCTAssertTrue(formatter.calls.isEmpty)

        subject.value = "first"
        formatter.prefix = "object-b"
        XCTAssertEqual(
            strings(try resolve(text)).joined(),
            "object-b:first"
        )

        subject.value = "second"
        formatter.prefix = "object-c"
        XCTAssertEqual(
            strings(try resolve(text)).joined(),
            "object-c:second"
        )

        formatter.returnsNil = true
        XCTAssertTrue(strings(try resolve(text)).isEmpty)
        XCTAssertEqual(
            formatter.calls,
            ["object:first", "object:second", "object:second"]
        )
    }

    func testReferenceConvertibleBridgesAtConstruction() throws {
        var date = Date(timeIntervalSince1970: 1234)
        let formatter = RecordingTextFormatter(prefix: "date-a")
        let text = Text(date, formatter: formatter)
        XCTAssertTrue(formatter.calls.isEmpty)

        date = Date(timeIntervalSince1970: 5678)
        formatter.prefix = "date-b"
        XCTAssertEqual(strings(try resolve(text)).joined(), "date-b:1234")
        XCTAssertEqual(formatter.calls, ["date:1234"])
        XCTAssertEqual(Int(date.timeIntervalSince1970), 5678)
    }

    func testEqualityUsesObjectThenFormatterEquality() {
        let equalSubject = EqualityFormatterSubject(1)
        let equalFormatter = EqualityTextFormatter(1)
        XCTAssertEqual(
            Text(equalSubject, formatter: equalFormatter),
            Text(
                EqualityFormatterSubject(1),
                formatter: EqualityTextFormatter(1)
            )
        )
        XCTAssertEqual(equalSubject.equalityCalls, 1)
        XCTAssertEqual(equalFormatter.equalityCalls, 1)

        let unequalSubject = EqualityFormatterSubject(1)
        let skippedFormatter = EqualityTextFormatter(1)
        XCTAssertNotEqual(
            Text(unequalSubject, formatter: skippedFormatter),
            Text(
                EqualityFormatterSubject(2),
                formatter: EqualityTextFormatter(1)
            )
        )
        XCTAssertEqual(unequalSubject.equalityCalls, 1)
        XCTAssertEqual(skippedFormatter.equalityCalls, 0)

        let equalSecondSubject = EqualityFormatterSubject(1)
        let unequalFormatter = EqualityTextFormatter(1)
        XCTAssertNotEqual(
            Text(equalSecondSubject, formatter: unequalFormatter),
            Text(
                EqualityFormatterSubject(1),
                formatter: EqualityTextFormatter(2)
            )
        )
        XCTAssertEqual(equalSecondSubject.equalityCalls, 1)
        XCTAssertEqual(unequalFormatter.equalityCalls, 1)
    }

    func testEnvironmentConfiguresFoundationFormatterFamilies() throws {
        let environment = configuredEnvironment()
        let calendar: [String: Any] = [
            "identifier": "buddhist",
            "locale": "de_DE",
            "timeZone": -10800,
        ]

        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US")
        date.calendar = Calendar(identifier: .gregorian)
        date.timeZone = TimeZone(secondsFromGMT: -8 * 3600)
        date.dateStyle = .full
        date.timeStyle = .full
        XCTAssertEqual(
            strings(try resolve(
                Text(Date(timeIntervalSince1970: 1234), formatter: date),
                environment: environment
            )).joined(),
            "jeudi 1 janvier 2513 E. B. à 09:20:34 UTC+09:00"
        )
        XCTAssertEqual(date.locale?.identifier, "fr_FR")
        XCTAssertEqual(calendarSnapshot(date.calendar), calendar as NSDictionary)
        XCTAssertEqual(date.timeZone.secondsFromGMT(), 32400)

        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: -8 * 3600)
        XCTAssertEqual(
            strings(try resolve(
                Text(Date(timeIntervalSince1970: 1234), formatter: iso),
                environment: environment
            )).joined(),
            "1970-01-01T09:20:34+09:00"
        )
        XCTAssertEqual(iso.timeZone.secondsFromGMT(), 32400)

        let components = DateComponentsFormatter()
        components.calendar = Calendar(identifier: .gregorian)
        components.allowedUnits = [.day, .hour, .minute]
        XCTAssertEqual(
            strings(try resolve(
                Text(
                    DateComponents(day: 2, hour: 3),
                    formatter: components
                ),
                environment: environment
            )).joined(),
            "2d 3:00"
        )
        XCTAssertEqual(
            calendarSnapshot(try XCTUnwrap(components.calendar)),
            calendar as NSDictionary
        )

        let interval = DateIntervalFormatter()
        interval.locale = Locale(identifier: "en_US")
        interval.calendar = Calendar(identifier: .gregorian)
        interval.timeZone = TimeZone(secondsFromGMT: -8 * 3600)
        interval.dateStyle = .short
        interval.timeStyle = .short
        XCTAssertEqual(
            strings(try resolve(
                Text(
                    DateInterval(
                        start: Date(timeIntervalSince1970: 1234),
                        duration: 3600
                    ),
                    formatter: interval
                ),
                environment: environment
            )).joined(),
            "01/01/2513 EB, 09:20 – 10:20"
        )
        XCTAssertEqual(interval.locale.identifier, "fr_FR")
        XCTAssertEqual(
            calendarSnapshot(interval.calendar),
            calendar as NSDictionary
        )
        XCTAssertEqual(interval.timeZone.secondsFromGMT(), 32400)

        let number = NumberFormatter()
        number.locale = Locale(identifier: "en_US")
        number.numberStyle = .currency
        XCTAssertEqual(
            strings(try resolve(
                Text(NSNumber(value: 1234.5), formatter: number),
                environment: environment
            )).joined(),
            "1 234,50 €"
        )
        XCTAssertEqual(number.locale.identifier, "fr_FR")

        let measurement = MeasurementFormatter()
        measurement.locale = Locale(identifier: "en_US")
        XCTAssertEqual(
            strings(try resolve(
                Text(
                    Measurement(value: 1.25, unit: UnitLength.meters),
                    formatter: measurement
                ),
                environment: environment
            )).joined(),
            "0,001 km"
        )
        XCTAssertEqual(measurement.locale.identifier, "fr_FR")

        let mass = MassFormatter()
        XCTAssertEqual(
            strings(try resolve(
                Text(NSNumber(value: 80), formatter: mass),
                environment: environment
            )).joined(),
            "80 kg"
        )
        let massNumberFormatter = try XCTUnwrap(
            mass.value(forKey: "numberFormatter") as? NumberFormatter
        )
        XCTAssertEqual(massNumberFormatter.locale.identifier, "fr_FR")
    }

    private func configuredEnvironment() -> EnvironmentValues {
        var environment = resolutionEnvironment()
        environment.locale = Locale(identifier: "fr_FR")
        var calendar = Calendar(identifier: .buddhist)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3600)!
        environment.calendar = calendar
        environment.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return environment
    }

    private func resolutionEnvironment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.font = .system(size: 23)
        environment.defaultFontRenderingMode = .vector()
        return environment
    }

    private func resolve(
        _ text: Text,
        environment: EnvironmentValues? = nil
    ) throws -> ResolvedTextSource {
        try XCTUnwrap(
            text._resolve(
                context: GraphTextResolutionContext(
                    environment: environment ?? resolutionEnvironment(),
                    sceneResources: sceneResources
                ),
                referenceDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private func strings(_ source: ResolvedTextSource) -> [String] {
        source.runs.compactMap { run in
            switch run {
            case let .text(_, string),
                 let .attributedText(_, string, _),
                 let .styledText(_, string, _, _):
                string
            case .attachment, .attributedAttachment, .styledAttachment:
                nil
            }
        }
    }

    private func calendarSnapshot(_ calendar: Calendar) -> NSDictionary {
        [
            "identifier": String(describing: calendar.identifier),
            "locale": calendar.locale?.identifier ?? "nil",
            "timeZone": calendar.timeZone.secondsFromGMT(),
        ] as NSDictionary
    }
}

private final class MutableFormatterSubject: NSObject {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

private final class RecordingTextFormatter: Formatter {
    var prefix: String
    var returnsNil = false
    var calls: [String] = []

    init(prefix: String) {
        self.prefix = prefix
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func string(for obj: Any?) -> String? {
        if let subject = obj as? MutableFormatterSubject {
            calls.append("object:\(subject.value)")
            return returnsNil ? nil : "\(prefix):\(subject.value)"
        }
        if let date = obj as? NSDate {
            let seconds = Int(date.timeIntervalSince1970)
            calls.append("date:\(seconds)")
            return returnsNil ? nil : "\(prefix):\(seconds)"
        }
        return nil
    }
}

private final class EqualityFormatterSubject: NSObject {
    let key: Int
    var equalityCalls = 0

    init(_ key: Int) {
        self.key = key
    }

    override func isEqual(_ object: Any?) -> Bool {
        equalityCalls += 1
        return (object as? EqualityFormatterSubject)?.key == key
    }
}

private final class EqualityTextFormatter: Formatter {
    let key: Int
    var equalityCalls = 0

    init(_ key: Int) {
        self.key = key
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func string(for obj: Any?) -> String? { "unused" }

    override func isEqual(_ object: Any?) -> Bool {
        equalityCalls += 1
        return (object as? EqualityTextFormatter)?.key == key
    }
}
