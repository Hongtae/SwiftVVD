import Foundation
import XCTest
@testable import VUI

final class LocalizedStringKeyTests: XCTestCase {
    private final class MutableFormatSubject: NSObject {
        var value: String

        init(_ value: String) {
            self.value = value
        }
    }

    private final class RecordingFormatter: Formatter {
        var prefix: String
        private(set) var calls: [String] = []

        init(prefix: String) {
            self.prefix = prefix
            super.init()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func string(for obj: Any?) -> String? {
            guard let subject = obj as? MutableFormatSubject else { return nil }
            let output = "\(prefix):\(subject.value)"
            calls.append(output)
            return output
        }
    }

    private final class NeverEqualFormatter: Formatter {
        override func isEqual(_ object: Any?) -> Bool {
            false
        }
    }

    private struct AttributedIntegerStyle: FormatStyle {
        func format(_ value: Int) -> AttributedString {
            var result = AttributedString("value \(value)")
            result.foregroundColor = VUI.Color.red
            return result
        }
    }

    func testCarrierLayoutAndFieldsMatchObservedShape() {
        XCTAssertEqual(MemoryLayout<LocalizedStringKey>.size, 32)
        XCTAssertEqual(MemoryLayout<LocalizedStringKey>.stride, 32)
        XCTAssertEqual(MemoryLayout<LocalizedStringKey>.alignment, 8)

        let plain = LocalizedStringKey("plain")
        XCTAssertEqual(plain.key, "plain")
        XCTAssertFalse(plain.hasFormatting)
        XCTAssertEqual(
            Mirror(reflecting: plain).children.compactMap(\.label),
            ["key", "hasFormatting", "arguments"]
        )

        let value = 42
        let interpolated: LocalizedStringKey = "integer \(value)"
        XCTAssertEqual(interpolated.key, "integer %lld")
        XCTAssertTrue(interpolated.hasFormatting)
        let arguments = Mirror(reflecting: interpolated).children
            .first { $0.label == "arguments" }
            .map { Mirror(reflecting: $0.value).children.count }
        XCTAssertEqual(arguments, 1)
    }

    func testValueArgumentEqualityUsesRawStorageAndFormatterEquality() {
        let first: LocalizedStringKey = "integer \(42)"
        let copied = first
        let different: LocalizedStringKey = "integer \(43)"
        let attributedFirst: LocalizedStringKey = "attributed \(AttributedString("value"))"
        let attributedSecond: LocalizedStringKey = "attributed \(AttributedString("value"))"
        let formattedFirst: LocalizedStringKey = "formatted \(42, format: .number)"
        let formattedSecond: LocalizedStringKey = "formatted \(42, format: .number)"
        var interpolation = LocalizedStringKey.StringInterpolation(
            literalCapacity: 8,
            interpolationCount: 1
        )
        interpolation.appendLiteral("integer ")
        interpolation.appendInterpolation(42)

        XCTAssertEqual(first, first)
        XCTAssertEqual(first, copied)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(LocalizedStringKey("literal"), LocalizedStringKey("literal"))
        XCTAssertEqual(attributedFirst, attributedSecond)
        XCTAssertEqual(formattedFirst, formattedSecond)
        XCTAssertEqual(
            LocalizedStringKey(stringInterpolation: interpolation),
            LocalizedStringKey(stringInterpolation: interpolation)
        )

        guard case let .value(firstValue, nil) = first.arguments[0].storage else {
            return XCTFail("Expected unformatted value argument storage")
        }
        XCTAssertEqual(String(reflecting: type(of: firstValue)), "Swift.Int64")

        let rawValue: any CVarArg = Int64(42)
        let neverEqual = LocalizedStringKey.FormatArgument(
            storage: .value(rawValue, NeverEqualFormatter())
        )
        let neverEqualCopy = neverEqual
        XCTAssertNotEqual(neverEqual, neverEqualCopy)
    }

    func testLiteralAndRuntimeStringChooseDifferentTextStorage() {
        let literal = Text("literal")
        let runtimeValue = "runtime"
        let runtime = Text(runtimeValue)

        guard case let .anyTextStorage(storage) = literal.storage else {
            return XCTFail("A string literal should create localized text storage")
        }
        XCTAssertTrue(storage is LocalizedTextStorage)

        guard case let .verbatim(value) = runtime.storage else {
            return XCTFail("A runtime string should create verbatim text storage")
        }
        XCTAssertEqual(value, runtimeValue)
    }

    func testFoundationFallbackFormatsScalarAndFormatStyleArguments() {
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_US")

        let integer = 42
        XCTAssertEqual(Text("integer \(integer)")._resolveText(in: environment), "integer 42")

        let value = 1_234
        XCTAssertEqual(
            Text("formatted \(value, format: .number)")._resolveText(in: environment),
            "formatted 1,234"
        )

        environment.locale = Locale(identifier: "de_DE")
        XCTAssertEqual(
            Text("formatted \(value, format: .number)")._resolveText(in: environment),
            "formatted 1.234"
        )
    }

    func testFormatterAndSubjectAreEvaluatedAtEachResolution() {
        let subject = MutableFormatSubject("initial")
        let formatter = RecordingFormatter(prefix: "first")
        let key: LocalizedStringKey = "value \(subject, formatter: formatter)"
        let text = Text(key)
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_US")

        XCTAssertTrue(formatter.calls.isEmpty)

        subject.value = "before-first-resolve"
        formatter.prefix = "second"
        XCTAssertEqual(
            text._resolveText(in: environment),
            "value second:before-first-resolve"
        )
        XCTAssertEqual(formatter.calls, ["second:before-first-resolve"])

        subject.value = "before-second-resolve"
        formatter.prefix = "third"
        XCTAssertEqual(
            text._resolveText(in: environment),
            "value third:before-second-resolve"
        )
        XCTAssertEqual(
            formatter.calls,
            ["second:before-first-resolve", "third:before-second-resolve"]
        )
    }

    func testLocalizedPlaceholderPresentationIntentUsesArgumentPrecedence() {
        func resolvedTextArgument(_ key: LocalizedStringKey) -> Text {
            let segments = key.resolve(
                table: nil,
                bundle: .module,
                locale: Locale(identifier: "en_US")
            )
            guard case let .text(text)? = segments.first else {
                XCTFail("Expected a localized Text argument")
                return Text(verbatim: "")
            }
            return text
        }

        func resolvedAttributedArgument(_ key: LocalizedStringKey) -> AttributedString {
            let segments = key.resolve(
                table: nil,
                bundle: .module,
                locale: Locale(identifier: "en_US")
            )
            guard case let .attributedString(value)? = segments.first else {
                XCTFail("Expected a localized AttributedString argument")
                return AttributedString()
            }
            return value
        }

        let plain = Text(verbatim: "value")
        let strong: LocalizedStringKey = "**\(plain)**"
        let strongFalse: LocalizedStringKey = "**\(plain.bold(false))**"
        let strongRegularWeight: LocalizedStringKey =
            "**\(plain.fontWeight(.regular))**"
        let strongRegularFont: LocalizedStringKey =
            "**\(plain.font(.system(size: 20, weight: .regular)))**"
        let emphasis: LocalizedStringKey = "*\(plain)*"
        let emphasisFalse: LocalizedStringKey = "*\(plain.italic(false))*"

        XCTAssertEqual(resolvedTextArgument(strong).boldValue, true)
        XCTAssertEqual(resolvedTextArgument(strongFalse).boldValue, false)
        XCTAssertNil(resolvedTextArgument(strongRegularWeight).boldValue)
        XCTAssertEqual(
            resolvedTextArgument(strongRegularWeight).fontWeight,
            .regular
        )
        XCTAssertEqual(resolvedTextArgument(strongRegularFont).boldValue, true)
        XCTAssertEqual(resolvedTextArgument(emphasis).italicValue, true)
        XCTAssertEqual(resolvedTextArgument(emphasisFalse).italicValue, false)

        let attributed = AttributedString("value")
        let strongAttributed: LocalizedStringKey = "**\(attributed)**"
        let emphasisAttributed: LocalizedStringKey = "*\(attributed)*"
        var attributedRegularFont = attributed
        attributedRegularFont.font = .system(size: 20, weight: .regular)
        let strongRegularFontAttributed: LocalizedStringKey =
            "**\(attributedRegularFont)**"

        let resolvedStrongAttributed = resolvedAttributedArgument(strongAttributed)
        XCTAssertTrue(resolvedStrongAttributed.runs.allSatisfy {
            $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
        let resolvedEmphasisAttributed = resolvedAttributedArgument(emphasisAttributed)
        XCTAssertTrue(resolvedEmphasisAttributed.runs.allSatisfy {
            $0.inlinePresentationIntent?.contains(.emphasized) == true
        })
        let resolvedStrongRegularFont = resolvedAttributedArgument(
            strongRegularFontAttributed
        )
        XCTAssertTrue(resolvedStrongRegularFont.runs.allSatisfy {
            $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
        XCTAssertTrue(resolvedStrongRegularFont.runs.allSatisfy {
            $0.font == Font.system(size: 20, weight: .regular)
        })

        guard let boldProvider = Font.system(size: 20).bold().provider.fontBox
                as? SystemFontProvider,
              let italicProvider = Font.system(size: 20).italic().provider.fontBox
                as? SystemFontProvider else {
            return XCTFail("Expected system font modifier providers")
        }
        XCTAssertEqual(boldProvider.weight, .bold)
        XCTAssertFalse(boldProvider.isItalic)
        XCTAssertTrue(italicProvider.isItalic)
    }

    func testFormatSpecifiableLookupSpecifiers() {
        let int: LocalizedStringKey = "\(Int(1))"
        let int8: LocalizedStringKey = "\(Int8(1))"
        let int16: LocalizedStringKey = "\(Int16(1))"
        let int32: LocalizedStringKey = "\(Int32(1))"
        let int64: LocalizedStringKey = "\(Int64(1))"
        let uint: LocalizedStringKey = "\(UInt(1))"
        let uint8: LocalizedStringKey = "\(UInt8(1))"
        let uint16: LocalizedStringKey = "\(UInt16(1))"
        let uint32: LocalizedStringKey = "\(UInt32(1))"
        let uint64: LocalizedStringKey = "\(UInt64(1))"
        let float: LocalizedStringKey = "\(Float(1))"
        let double: LocalizedStringKey = "\(Double(1))"
        let cgFloat: LocalizedStringKey = "\(CGFloat(1))"

        XCTAssertEqual(int.key, "%lld")
        XCTAssertEqual(int8.key, "%d")
        XCTAssertEqual(int16.key, "%d")
        XCTAssertEqual(int32.key, "%d")
        XCTAssertEqual(int64.key, "%lld")
        XCTAssertEqual(uint.key, "%llu")
        XCTAssertEqual(uint8.key, "%u")
        XCTAssertEqual(uint16.key, "%u")
        XCTAssertEqual(uint32.key, "%u")
        XCTAssertEqual(uint64.key, "%llu")
        XCTAssertEqual(float.key, "%f")
        XCTAssertEqual(double.key, "%lf")
        XCTAssertEqual(cgFloat.key, "%lf")
    }

    func testBundleTableAndEnvironmentLocaleAreDeferredUntilResolution() {
        let greeting: LocalizedStringKey = "greeting"
        let count = 3
        let items: LocalizedStringKey = "items \(count)"
        let customTable: LocalizedStringKey = "custom-table"
        var environment = EnvironmentValues()

        environment.locale = Locale(identifier: "en")
        XCTAssertEqual(Text(greeting, bundle: .module)._resolveText(in: environment), "Hello")
        XCTAssertEqual(Text(items, bundle: .module)._resolveText(in: environment), "3 items")
        XCTAssertEqual(
            Text(customTable, tableName: "Interface", bundle: .module)
                ._resolveText(in: environment),
            "Custom table"
        )

        environment.locale = Locale(identifier: "ko")
        XCTAssertEqual(Text(greeting, bundle: .module)._resolveText(in: environment), "안녕하세요")
        XCTAssertEqual(Text(items, bundle: .module)._resolveText(in: environment), "항목 3개")
    }

    func testStringDictionaryPluralRulesAreResolvedByFoundation() {
        func apples(_ count: Int) -> Text {
            let key: LocalizedStringKey = "apples \(count)"
            return Text(key, bundle: .module)
        }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en")
        XCTAssertEqual(apples(1)._resolveText(in: environment), "1 apple")
        XCTAssertEqual(apples(2)._resolveText(in: environment), "2 apples")

        environment.locale = Locale(identifier: "ko")
        XCTAssertEqual(apples(1)._resolveText(in: environment), "사과 1개")
        XCTAssertEqual(apples(2)._resolveText(in: environment), "사과 2개")
    }

    func testInterpolationStorageFamiliesAndTextTokenSequence() {
        let integer = 1
        let first = Text(verbatim: "first")
        let attributed = AttributedString("styled")
        let image = Image("star")
        let second = Text(verbatim: "second")
        let key: LocalizedStringKey =
            "mixed \(integer) \(first) \(attributed) \(image) \(second)"

        XCTAssertEqual(key.key, "mixed %lld %@ %@ %@ %@")
        XCTAssertEqual(key.arguments.count, 5)
        guard case .value = key.arguments[0].storage else {
            return XCTFail("A scalar should use value storage")
        }
        guard case let .text(storedFirst, firstToken) = key.arguments[1].storage else {
            return XCTFail("Text should use tokenized text storage")
        }
        XCTAssertEqual(storedFirst, first)
        XCTAssertEqual(firstToken.id, 0)
        guard case let .attributedString(storedAttributed) = key.arguments[2].storage else {
            return XCTFail("AttributedString should use attributed storage")
        }
        XCTAssertEqual(storedAttributed, attributed)
        guard case let .text(storedImage, imageToken) = key.arguments[3].storage else {
            return XCTFail("Image should be retained as tokenized Text")
        }
        XCTAssertEqual(storedImage, Text(image))
        XCTAssertEqual(imageToken.id, 1)
        guard case let .text(storedSecond, secondToken) = key.arguments[4].storage else {
            return XCTFail("Text should use tokenized text storage")
        }
        XCTAssertEqual(storedSecond, second)
        XCTAssertEqual(secondToken.id, 2)
    }

    func testStringInterpolationFieldsAndPercentEscaping() {
        let value = 3
        let key: LocalizedStringKey = "literal %d and %@ \(value)"
        XCTAssertEqual(key.key, "literal %%d and %%@ %lld")
        XCTAssertEqual(
            Mirror(reflecting: LocalizedStringKey.StringInterpolation(
                literalCapacity: 0,
                interpolationCount: 0
            )).children.compactMap(\.label),
            ["key", "arguments", "seed"]
        )

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_US")
        XCTAssertEqual(
            Text(key)._resolveText(in: environment),
            "literal %d and %@ 3"
        )
    }

    func testRichArgumentsFollowLocalizedReorderingAndRepetition() {
        let embedded = Text(verbatim: "first")
        var attributed = AttributedString("styled")
        attributed.foregroundColor = VUI.Color.red
        let count = 7
        let key: LocalizedStringKey = "rich \(embedded) \(count) \(attributed)"
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en")

        XCTAssertEqual(
            Text(key, bundle: .module)._resolveText(in: environment),
            "styled | 7 | first | styled"
        )

        let segments = key.resolve(table: nil, bundle: .module, locale: environment.locale)
        let textSegments = segments.compactMap { segment -> Text? in
            guard case let .text(text) = segment else { return nil }
            return text
        }
        let redRuns = segments.flatMap { segment -> [String] in
            guard case let .attributedString(value) = segment else { return [] }
            return value.runs.compactMap { run in
                guard run.foregroundColor == VUI.Color.red else { return nil }
                return String(value.characters[run.range])
            }
        }
        XCTAssertEqual(textSegments, [embedded])
        XCTAssertEqual(redRuns, ["styled", "styled"])
    }

    func testFormatStyleArgumentsRetainTextAndAttributedOutput() {
        let stringKey: LocalizedStringKey = "formatted \(1_234, format: .number)"
        guard case let .text(stringText, stringToken) = stringKey.arguments[0].storage else {
            return XCTFail("String FormatStyle should be retained as Text")
        }
        XCTAssertEqual(stringToken.id, 0)

        let attributedKey: LocalizedStringKey =
            "formatted \(5, format: AttributedIntegerStyle())"
        guard case let .text(attributedText, attributedToken) =
            attributedKey.arguments[0].storage else {
            return XCTFail("Attributed FormatStyle should be retained as Text")
        }
        XCTAssertEqual(attributedToken.id, 0)

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_US")
        XCTAssertEqual(stringText._resolveText(in: environment), "1,234")
        XCTAssertEqual(attributedText._resolveText(in: environment), "value 5")
    }

    func testResourceDateTimerAndTimeSourceStorageFamilies() {
        let resource = LocalizedStringResource("resource")
        let resourceKey: LocalizedStringKey = "resource \(resource)"
        guard case let .localizedStringResource(storedResource) =
            resourceKey.arguments[0].storage else {
            return XCTFail("LocalizedStringResource should retain resource storage")
        }
        XCTAssertEqual(storedResource, resource)
        guard case let .anyTextStorage(resourceStorage) = Text(resource).storage else {
            return XCTFail("Text should retain localized resource storage")
        }
        XCTAssertEqual(
            String(describing: type(of: resourceStorage)),
            "LocalizedStringResourceStorage"
        )

        let date = Date(timeIntervalSinceReferenceDate: 0)
        let dateKey: LocalizedStringKey = "date \(date, style: .date)"
        guard case let .text(_, dateToken) = dateKey.arguments[0].storage else {
            return XCTFail("Date style should be retained as Text")
        }
        XCTAssertEqual(dateToken.id, 0)

        let interval = date...date.addingTimeInterval(3_600)
        let timerKey: LocalizedStringKey = "timer \(timerInterval: interval)"
        guard case let .text(_, timerToken) = timerKey.arguments[0].storage else {
            return XCTFail("Timer interval should be retained as Text")
        }
        XCTAssertEqual(timerToken.id, 0)

        let sourceKey: LocalizedStringKey =
            "source \(TimeDataSource<Date>.currentDate, format: Date.FormatStyle.dateTime)"
        guard case let .text(_, sourceToken) = sourceKey.arguments[0].storage else {
            return XCTFail("TimeDataSource should be retained as Text")
        }
        XCTAssertEqual(sourceToken.id, 0)
    }

    func testDateIntervalStorageInterpolationAndEnvironmentFormatting() {
        let defaults = EnvironmentValues()
        XCTAssertEqual(defaults.calendar, Calendar.autoupdatingCurrent)
        XCTAssertEqual(defaults.timeZone, TimeZone.autoupdatingCurrent)

        var sourceCalendar = Calendar(identifier: .gregorian)
        let gmt = TimeZone(secondsFromGMT: 0)!
        sourceCalendar.timeZone = gmt
        let start = sourceCalendar.date(from: DateComponents(
            year: 2024,
            month: 1,
            day: 15,
            hour: 10,
            minute: 30
        ))!
        let sameDayEnd = sourceCalendar.date(from: DateComponents(
            year: 2024,
            month: 1,
            day: 15,
            hour: 12
        ))!
        let nextDayEnd = sourceCalendar.date(from: DateComponents(
            year: 2024,
            month: 1,
            day: 16,
            hour: 12
        ))!

        let rangeText = Text(start...sameDayEnd)
        guard case let .anyTextStorage(rangeStorage) = rangeText.storage else {
            return XCTFail("A date range should use date text storage")
        }
        XCTAssertEqual(String(describing: type(of: rangeStorage)), "DateTextStorage")
        XCTAssertEqual(
            Mirror(reflecting: rangeStorage).children.compactMap(\.label),
            ["storage"]
        )
        let storedValue = Mirror(reflecting: rangeStorage).children.first!.value
        XCTAssertEqual(
            Mirror(reflecting: storedValue).children.compactMap(\.label),
            ["interval"]
        )

        let interval = DateInterval(start: start, end: sameDayEnd)
        XCTAssertEqual(rangeText, Text(interval))

        let rangeKey: LocalizedStringKey = "range \(start...sameDayEnd)"
        let intervalKey: LocalizedStringKey = "interval \(interval)"
        guard case let .text(_, rangeToken) = rangeKey.arguments[0].storage,
              case let .text(_, intervalToken) = intervalKey.arguments[0].storage else {
            return XCTFail("Date intervals should use tokenized text arguments")
        }
        XCTAssertEqual(rangeKey.key, "range %@")
        XCTAssertEqual(intervalKey.key, "interval %@")
        XCTAssertEqual(rangeToken.id, 0)
        XCTAssertEqual(intervalToken.id, 0)

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_US")
        environment.calendar = sourceCalendar
        environment.timeZone = gmt
        XCTAssertEqual(rangeText._resolveText(in: environment), "10:30 AM–12:00 PM")
        XCTAssertEqual(
            Text(start...nextDayEnd)._resolveText(in: environment),
            "Jan 15 – Jan 16"
        )

        environment.locale = Locale(identifier: "ko_KR")
        XCTAssertEqual(rangeText._resolveText(in: environment), "오전 10:30–오후 12:00")
        XCTAssertEqual(
            Text(start...nextDayEnd)._resolveText(in: environment),
            "1월 15일 – 1월 16일"
        )

        environment.locale = Locale(identifier: "en_US")
        environment.calendar = Calendar(identifier: .islamicCivil)
        XCTAssertEqual(
            Text(start...nextDayEnd)._resolveText(in: environment),
            "Rajb. 4 – Rajb. 5"
        )

        environment.calendar = sourceCalendar
        environment.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(rangeText._resolveText(in: environment), "2:30–4:00 AM")
    }

    func testEmbeddedTextForegroundBecomesRunSpecificStyle() {
        let embedded = Text(verbatim: "red").foregroundColor(VUI.Color.red)
        let key: LocalizedStringKey = "value \(embedded)"
        guard case let .text(stored, _) = key.arguments[0].storage else {
            return XCTFail("Embedded Text should use text storage")
        }
        XCTAssertEqual(stored.foregroundColor, VUI.Color.red)

        let plain = GraphicsContext.ResolvedText.Run.text([], "red")
            .applying(foregroundColor: VUI.Color.red)
        guard case let .styledText(_, _, _, plainStyle) = plain else {
            return XCTFail("Embedded foreground should create a styled text run")
        }
        XCTAssertEqual(plainStyle.foregroundColor, VUI.Color.red)

        let existing = GraphicsContext.ResolvedText.Run.styledText(
            [],
            "blue",
            _TextAttributeValues(),
            _ResolvedTextRunAttributes(foregroundColor: VUI.Color.blue)
        ).applying(foregroundColor: VUI.Color.red)
        guard case let .styledText(_, _, _, existingStyle) = existing else {
            return XCTFail("Attributed foreground should remain styled text")
        }
        XCTAssertEqual(existingStyle.foregroundColor, VUI.Color.blue)
    }
}
