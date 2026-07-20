import Foundation
import XCTest
@testable import VUI

final class LocalizedStringKeyTests: XCTestCase {
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
}
