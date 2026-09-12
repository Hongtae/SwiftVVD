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

    private struct LocalizationRunRecord: Equatable {
        var text: String
        var replacementIndex: Int?
        var intentRawValue: UInt?
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

    #if canImport(Darwin)
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
    #endif

    func testLocalizedPlaceholderPresentationIntentUsesArgumentPrecedence() {
        func resolvedTextArgument(_ key: LocalizedStringKey) -> Text {
            var environment = EnvironmentValues()
            environment.locale = Locale(identifier: "en_US")
            let segments = key.resolve(
                table: nil,
                bundle: .module,
                environment: environment
            )
            guard case let .text(text)? = segments.first else {
                XCTFail("Expected a localized Text argument")
                return Text(verbatim: "")
            }
            return text
        }

        #if canImport(Darwin)
        func resolvedAttributedArgument(
            _ key: LocalizedStringKey
        ) -> AttributedString {
            var environment = EnvironmentValues()
            environment.locale = Locale(identifier: "en_US")
            let segments = key.resolve(
                table: nil,
                bundle: .module,
                environment: environment
            )
            guard case let .attributedString(value)? = segments.first else {
                XCTFail("Expected a localized AttributedString argument")
                return AttributedString()
            }
            return value
        }
        #endif

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
        attributedRegularFont.font = VUI.Font.system(size: 20, weight: .regular)
        let strongRegularFontAttributed: LocalizedStringKey =
            "**\(attributedRegularFont)**"

        #if canImport(Darwin)
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
        #else
        XCTAssertEqual(resolvedTextArgument(strongAttributed).boldValue, true)
        XCTAssertEqual(resolvedTextArgument(emphasisAttributed).italicValue, true)
        XCTAssertEqual(
            resolvedTextArgument(strongRegularFontAttributed).boldValue,
            true
        )
        #endif

        guard let boldProvider = Font.system(size: 20).bold().resolved(in: EnvironmentValues()).typefaceProvider
                as? SystemFontProvider,
              let italicProvider = Font.system(size: 20).italic().resolved(in: EnvironmentValues()).typefaceProvider
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

    func testCompatibilityLocaleMatcherMatchesFoundationSamples() {
        let samples: [(available: [String], preference: String)] = [
            (["en", "ko"], "ko"),
            (["en", "ko"], "ko_KR"),
            (["en", "ko"], "en_US"),
            (["en-GB", "fr"], "en_AU"),
            (["zh-Hans", "zh-Hant"], "zh_Hant_TW"),
            (["zh-Hans", "zh-Hant"], "zh_TW"),
        ]

        for sample in samples {
            XCTAssertEqual(
                LocalizationResolver.explicitLocalization(
                    from: sample.available,
                    for: Locale(identifier: sample.preference)
                ),
                Bundle.preferredLocalizations(
                    from: sample.available,
                    forPreferences: [sample.preference]
                ).first,
                "\(sample.available), \(sample.preference)"
            )
        }
        XCTAssertNil(LocalizationResolver.explicitLocalization(
            from: ["en", "ko"],
            for: Locale(identifier: "fr")
        ))
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

        let segments = key.resolve(table: nil, bundle: .module, environment: environment)
        let textSegments = segments.compactMap { segment -> Text? in
            guard case let .text(text) = segment else { return nil }
            return text
        }
        #if canImport(Darwin)
        let redRuns = segments.flatMap { segment -> [String] in
            guard case let .attributedString(value) = segment else { return [] }
            return value.runs.compactMap { run in
                guard run.foregroundColor == VUI.Color.red else { return nil }
                return String(value.characters[run.range])
            }
        }
        XCTAssertEqual(textSegments, [embedded])
        XCTAssertEqual(redRuns, ["styled", "styled"])
        #else
        XCTAssertEqual(
            textSegments.map { $0._resolveText(in: environment) },
            ["styled", "first", "styled"]
        )
        #endif
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

    func testPortableLocalizationCompatibilityCarriers() {
        let literal = _StringLocalizationValue("plain")
        XCTAssertEqual(literal.pattern, "plain")
        XCTAssertFalse(literal.hasFormatting)
        XCTAssertEqual(
            _StringLocalizationValue("value %lld").resolvedString(
                replacements: [Int64(42)],
                locale: Locale(identifier: "en_US")
            ),
            "value %lld"
        )

        var interpolation = _StringLocalizationValue.StringInterpolation(
            literalCapacity: 6,
            interpolationCount: 1
        )
        interpolation.appendLiteral("value ")
        interpolation.appendInterpolation(placeholder: .int, specifier: "%lld")
        let interpolated = _StringLocalizationValue(
            stringInterpolation: interpolation
        )
        XCTAssertEqual(interpolated.pattern, "value %lld")
        XCTAssertTrue(interpolated.hasFormatting)
        XCTAssertEqual(
            interpolated.resolvedString(
                replacements: [Int64(42)],
                locale: Locale(identifier: "en_US")
            ),
            "value 42"
        )
        let resolved = interpolated.resolvedLocalization(
            replacements: [Int64(42)],
            applyReplacementIndexAttribute: true,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(resolved.string, "value 42")
        XCTAssertEqual(
            resolved.runs.map {
                LocalizationRunRecord(
                    text: $0.text,
                    replacementIndex: $0.replacementIndex,
                    intentRawValue: $0.presentationIntent?.rawValue
                )
            },
            [
                LocalizationRunRecord(
                    text: "value ",
                    replacementIndex: nil,
                    intentRawValue: nil
                ),
                LocalizationRunRecord(
                    text: "42",
                    replacementIndex: 1,
                    intentRawValue: nil
                ),
            ]
        )
        XCTAssertEqual(
            String(interpolated.resolvedAttributedString(
                replacements: [Int64(42)],
                locale: Locale(identifier: "en_US")
            ).characters),
            "value 42"
        )

        let resource = _LocalizedStringResource(interpolated)
        XCTAssertEqual(resource, _LocalizedStringResource(interpolated))
        XCTAssertEqual(resource.value.pattern, "value %lld")

        var options = _AttributedStringLocalizationOptions()
        XCTAssertNil(options.replacements)
        XCTAssertFalse(options.applyReplacementIndexAttribute)
        options.replacements = [Int64(42)]
        options.applyReplacementIndexAttribute = true
        XCTAssertEqual(options.replacements?.count, 1)
        XCTAssertTrue(options.applyReplacementIndexAttribute)

        var intent = _InlinePresentationIntent.emphasized
        intent.formUnion(.stronglyEmphasized)
        XCTAssertTrue(intent.contains(.emphasized))
        XCTAssertTrue(intent.contains(.stronglyEmphasized))
        XCTAssertEqual(_InlinePresentationIntent.emphasized.rawValue, 1)
        XCTAssertEqual(_InlinePresentationIntent.stronglyEmphasized.rawValue, 2)
        XCTAssertEqual(
            AttributeScopes.FoundationAttributes
                .ReplacementIndexAttribute.name,
            "NSReplacementIndex"
        )
        XCTAssertEqual(
            _InlinePresentationIntentAttribute.name,
            "NSInlinePresentationIntent"
        )

        XCTAssertEqual(
            _StringLocalizationValue("greeting").resolvedString(
                bundle: .module,
                locale: Locale(identifier: "en")
            ),
            "Hello"
        )
        XCTAssertEqual(
            _StringLocalizationValue("greeting").resolvedString(
                bundle: .module,
                locale: Locale(identifier: "ko")
            ),
            "안녕하세요"
        )

        var pluralInterpolation =
            _StringLocalizationValue.StringInterpolation(
                literalCapacity: 7,
                interpolationCount: 1
            )
        pluralInterpolation.appendLiteral("apples ")
        pluralInterpolation.appendInterpolation(
            placeholder: .int,
            specifier: "%lld"
        )
        let plural = _StringLocalizationValue(
            stringInterpolation: pluralInterpolation
        )
        XCTAssertEqual(
            plural.resolvedString(
                replacements: [Int64(1)],
                bundle: .module,
                locale: Locale(identifier: "en")
            ),
            "1 apple"
        )
        XCTAssertEqual(
            plural.resolvedString(
                replacements: [Int64(2)],
                bundle: .module,
                locale: Locale(identifier: "ko")
            ),
            "사과 2개"
        )
    }

    #if canImport(Darwin)
    func testLocalizationCompatibilityTypesMatchFoundation() {
        let foundationOptions = AttributedString.LocalizationOptions()
        XCTAssertNil(foundationOptions.replacements)
        XCTAssertFalse(foundationOptions.applyReplacementIndexAttribute)
        XCTAssertEqual(
            _InlinePresentationIntent.emphasized.rawValue,
            InlinePresentationIntent.emphasized.rawValue
        )
        XCTAssertEqual(
            _InlinePresentationIntent.stronglyEmphasized.rawValue,
            InlinePresentationIntent.stronglyEmphasized.rawValue
        )
        XCTAssertEqual(
            _InlinePresentationIntentAttribute.name,
            AttributeScopes.FoundationAttributes
                .InlinePresentationIntentAttribute.name
        )
        var nativeLiteralOptions = AttributedString.LocalizationOptions()
        nativeLiteralOptions.replacements = [Int64(42)]
        nativeLiteralOptions.applyReplacementIndexAttribute = true
        let nativeLiteral = AttributedString(
            localized: String.LocalizationValue("literal %d"),
            options: nativeLiteralOptions,
            locale: Locale(identifier: "en_US")
        )
        let compatibilityLiteral =
            _StringLocalizationValue("literal %d").resolvedLocalization(
                replacements: [Int64(42)],
                applyReplacementIndexAttribute: true,
                locale: Locale(identifier: "en_US")
            )
        XCTAssertEqual(
            compatibilityLiteral.string,
            String(nativeLiteral.characters)
        )
        XCTAssertEqual(
            compatibilityLiteral.runs.map(\.replacementIndex),
            nativeLiteral.runs.map(\.replacementIndex)
        )
    }

    func testLocalizationResolverMatchesFoundationReplacementRuns() {
        // ASSERTIONS foundationLocalizationReplacementRunsObserved
        // ASSERTIONS foundationLocalizationStringsDictionaryObserved
        // ASSERTIONS foundationLocalizationLiteralFormatBoundaryObserved
        func nativeRecords(
            _ value: AttributedString
        ) -> [LocalizationRunRecord] {
            value.runs.map { run in
                LocalizationRunRecord(
                    text: String(value.characters[run.range]),
                    replacementIndex: run.replacementIndex,
                    intentRawValue: run.inlinePresentationIntent?.rawValue
                )
            }
        }

        func compatibilityRecords(
            _ value: LocalizationResolver.Result
        ) -> [LocalizationRunRecord] {
            value.runs.map { run in
                LocalizationRunRecord(
                    text: run.text,
                    replacementIndex: run.replacementIndex,
                    intentRawValue: run.presentationIntent?.rawValue
                )
            }
        }

        func makeNativeRichValue() -> String.LocalizationValue {
            var interpolation = String.LocalizationValue.StringInterpolation(
                literalCapacity: 10,
                interpolationCount: 3
            )
            interpolation.appendLiteral("rich ")
            interpolation.appendInterpolation(
                placeholder: .object,
                specifier: "%@"
            )
            interpolation.appendLiteral(" ")
            interpolation.appendInterpolation(
                placeholder: .int,
                specifier: "%lld"
            )
            interpolation.appendLiteral(" ")
            interpolation.appendInterpolation(
                placeholder: .object,
                specifier: "%@"
            )
            return String.LocalizationValue(
                stringInterpolation: interpolation
            )
        }

        func makeCompatibilityRichValue() -> _StringLocalizationValue {
            var interpolation =
                _StringLocalizationValue.StringInterpolation(
                    literalCapacity: 10,
                    interpolationCount: 3
                )
            interpolation.appendLiteral("rich ")
            interpolation.appendInterpolation(
                placeholder: .object,
                specifier: "%@"
            )
            interpolation.appendLiteral(" ")
            interpolation.appendInterpolation(
                placeholder: .int,
                specifier: "%lld"
            )
            interpolation.appendLiteral(" ")
            interpolation.appendInterpolation(
                placeholder: .object,
                specifier: "%@"
            )
            return _StringLocalizationValue(
                stringInterpolation: interpolation
            )
        }

        let locale = Locale(identifier: "en_US")
        let richReplacements: [any CVarArg] = [
            "first",
            Int64(7),
            "styled",
        ]
        var nativeRichOptions = AttributedString.LocalizationOptions()
        nativeRichOptions.replacements = richReplacements
        nativeRichOptions.applyReplacementIndexAttribute = true
        let nativeRich = AttributedString(
            localized: makeNativeRichValue(),
            options: nativeRichOptions,
            bundle: .module,
            locale: locale
        )
        let compatibilityRich =
            makeCompatibilityRichValue().resolvedLocalization(
                replacements: richReplacements,
                applyReplacementIndexAttribute: true,
                bundle: .module,
                locale: locale
            )
        XCTAssertEqual(
            compatibilityRecords(compatibilityRich),
            nativeRecords(nativeRich)
        )

        var nativeEscapedInterpolation =
            String.LocalizationValue.StringInterpolation(
                literalCapacity: 20,
                interpolationCount: 1
            )
        nativeEscapedInterpolation.appendLiteral("literal %d and %@ ")
        nativeEscapedInterpolation.appendInterpolation(
            placeholder: .int,
            specifier: "%lld"
        )
        let nativeEscapedValue = String.LocalizationValue(
            stringInterpolation: nativeEscapedInterpolation
        )
        var compatibilityEscapedInterpolation =
            _StringLocalizationValue.StringInterpolation(
                literalCapacity: 20,
                interpolationCount: 1
            )
        compatibilityEscapedInterpolation.appendLiteral("literal %d and %@ ")
        compatibilityEscapedInterpolation.appendInterpolation(
            placeholder: .int,
            specifier: "%lld"
        )
        let compatibilityEscapedValue = _StringLocalizationValue(
            stringInterpolation: compatibilityEscapedInterpolation
        )
        var nativeEscapedOptions = AttributedString.LocalizationOptions()
        nativeEscapedOptions.replacements = [Int64(3)]
        nativeEscapedOptions.applyReplacementIndexAttribute = true
        let nativeEscaped = AttributedString(
            localized: nativeEscapedValue,
            options: nativeEscapedOptions,
            locale: locale
        )
        let compatibilityEscaped =
            compatibilityEscapedValue.resolvedLocalization(
                replacements: [Int64(3)],
                applyReplacementIndexAttribute: true,
                locale: locale
            )
        XCTAssertEqual(
            compatibilityRecords(compatibilityEscaped),
            nativeRecords(nativeEscaped)
        )

        var nativeIntentInterpolation =
            String.LocalizationValue.StringInterpolation(
                literalCapacity: 6,
                interpolationCount: 1
            )
        nativeIntentInterpolation.appendLiteral("***")
        nativeIntentInterpolation.appendInterpolation(
            placeholder: .object,
            specifier: "%@"
        )
        nativeIntentInterpolation.appendLiteral("***")
        let nativeIntentValue = String.LocalizationValue(
            stringInterpolation: nativeIntentInterpolation
        )
        var compatibilityIntentInterpolation =
            _StringLocalizationValue.StringInterpolation(
                literalCapacity: 6,
                interpolationCount: 1
            )
        compatibilityIntentInterpolation.appendLiteral("***")
        compatibilityIntentInterpolation.appendInterpolation(
            placeholder: .object,
            specifier: "%@"
        )
        compatibilityIntentInterpolation.appendLiteral("***")
        let compatibilityIntentValue = _StringLocalizationValue(
            stringInterpolation: compatibilityIntentInterpolation
        )
        let intentReplacements: [any CVarArg] = ["\u{FFFC}"]
        var nativeIntentOptions = AttributedString.LocalizationOptions()
        nativeIntentOptions.replacements = intentReplacements
        nativeIntentOptions.applyReplacementIndexAttribute = true
        let nativeIntent = AttributedString(
            localized: nativeIntentValue,
            options: nativeIntentOptions,
            locale: locale
        )
        let compatibilityIntent =
            compatibilityIntentValue.resolvedLocalization(
                replacements: intentReplacements,
                applyReplacementIndexAttribute: true,
                locale: locale
            )
        XCTAssertEqual(
            compatibilityRecords(compatibilityIntent),
            nativeRecords(nativeIntent)
        )

        func makeNativePluralValue() -> String.LocalizationValue {
            var interpolation = String.LocalizationValue.StringInterpolation(
                literalCapacity: 7,
                interpolationCount: 1
            )
            interpolation.appendLiteral("apples ")
            interpolation.appendInterpolation(
                placeholder: .int,
                specifier: "%lld"
            )
            return String.LocalizationValue(
                stringInterpolation: interpolation
            )
        }

        func makeCompatibilityPluralValue() -> _StringLocalizationValue {
            var interpolation =
                _StringLocalizationValue.StringInterpolation(
                    literalCapacity: 7,
                    interpolationCount: 1
                )
            interpolation.appendLiteral("apples ")
            interpolation.appendInterpolation(
                placeholder: .int,
                specifier: "%lld"
            )
            return _StringLocalizationValue(
                stringInterpolation: interpolation
            )
        }

        for localeIdentifier in ["en", "ko"] {
            for count: Int64 in [1, 2] {
                let pluralLocale = Locale(identifier: localeIdentifier)
                guard let localizationPath = Bundle.module.path(
                    forResource: localeIdentifier,
                    ofType: "lproj"
                ),
                let localizedBundle = Bundle(path: localizationPath) else {
                    return XCTFail(
                        "Missing \(localeIdentifier) localization bundle"
                    )
                }
                let pluralReplacements: [any CVarArg] = [count]
                var nativePluralOptions =
                    AttributedString.LocalizationOptions()
                nativePluralOptions.replacements = pluralReplacements
                nativePluralOptions.applyReplacementIndexAttribute = true
                let nativePlural = AttributedString(
                    localized: makeNativePluralValue(),
                    options: nativePluralOptions,
                    bundle: localizedBundle,
                    locale: pluralLocale
                )
                let compatibilityPlural =
                    makeCompatibilityPluralValue().resolvedLocalization(
                        replacements: pluralReplacements,
                        applyReplacementIndexAttribute: true,
                        bundle: localizedBundle,
                        locale: pluralLocale
                    )
                XCTAssertEqual(
                    compatibilityRecords(compatibilityPlural),
                    nativeRecords(nativePlural),
                    "\(localeIdentifier) count \(count)"
                )

                guard case let .resolved(loadedPattern) =
                    LocalizationResolver.stringsDictionaryLookup(
                        forKey: "apples %lld",
                        table: nil,
                        bundle: .module,
                        localization: localeIdentifier,
                        locale: pluralLocale,
                        replacements: pluralReplacements
                    ) else {
                    return XCTFail(
                        "Failed to load \(localeIdentifier) strings dictionary"
                    )
                }
                let loadedPlural = LocalizationResolver.resolve(
                    pattern: loadedPattern,
                    replacements: pluralReplacements,
                    locale: pluralLocale,
                    applyReplacementIndexAttribute: true
                )
                XCTAssertEqual(
                    compatibilityRecords(loadedPlural),
                    nativeRecords(nativePlural),
                    "loaded \(localeIdentifier) count \(count)"
                )
            }
        }
    }
    #endif

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

        var style = Text.Style()
        for modifier in embedded.modifiers.reversed() { modifier.modify(style: &style) }
        var properties = Text.ResolvedProperties()
        XCTAssertEqual(style.nsAttributes(in: EnvironmentValues(), properties: &properties).foregroundColor, VUI.Color.red)
        var attributes = _ResolvedTextRunAttributes(foregroundColor: VUI.Color.blue).nsAttributes
        attributes.transferAttributedStringStyles(to: &style)
        XCTAssertEqual(style.nsAttributes(in: EnvironmentValues(), properties: &properties).foregroundColor, VUI.Color.blue)
    }
}
