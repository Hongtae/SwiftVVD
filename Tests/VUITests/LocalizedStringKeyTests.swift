import Foundation
import XCTest
@testable import VUI

final class LocalizedStringKeyTests: XCTestCase {
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

    func testEqualityPreservesInterpolatedArgumentIdentity() {
        let first: LocalizedStringKey = "integer \(42)"
        let copied = first
        let independentlyConstructed: LocalizedStringKey = "integer \(42)"
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
        XCTAssertNotEqual(first, independentlyConstructed)
        XCTAssertEqual(LocalizedStringKey("literal"), LocalizedStringKey("literal"))
        XCTAssertEqual(attributedFirst, attributedSecond)
        XCTAssertEqual(formattedFirst, formattedSecond)
        XCTAssertEqual(
            LocalizedStringKey(stringInterpolation: interpolation),
            LocalizedStringKey(stringInterpolation: interpolation)
        )
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
