//
//  File: LocalizedStringKey.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation {
    var key: String
    var hasFormatting: Bool = false
    var arguments: [FormatArgument]

    public init(_ value: String) {
        self.key = value
        self.arguments = []
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.key = stringInterpolation.key
        self.hasFormatting = !stringInterpolation.arguments.isEmpty
        self.arguments = stringInterpolation.arguments
    }

    struct FormatArgument: Equatable {
        struct Token: Equatable {
            var id: Int
        }

        enum Storage {
            case value(any CVarArg, Formatter?)
            case text(Text, Token)
            case attributedString(AttributedString)
            case localizedStringResource(LocalizedStringResource)
        }

        var storage: Storage

        static func == (lhs: FormatArgument, rhs: FormatArgument) -> Bool {
            switch (lhs.storage, rhs.storage) {
            case let (.value(lhs, lhsFormatter), .value(rhs, rhsFormatter)):
                guard lhsFormatter === rhsFormatter else { return false }
                if let lhs = lhs as? LocalizationValueArgument,
                   let rhs = rhs as? LocalizationValueArgument {
                    return lhs === rhs
                }
                return false
            case let (.text(lhs, lhsToken), .text(rhs, rhsToken)):
                return lhs == rhs && lhsToken == rhsToken
            case let (.attributedString(lhs), .attributedString(rhs)):
                return lhs == rhs
            case let (.localizedStringResource(lhs), .localizedStringResource(rhs)):
                return lhs == rhs
            default:
                return false
            }
        }
    }

    enum ResolvedSegment {
        case attributedString(AttributedString)
        case text(Text)
    }

    func resolve(
        table: String?,
        bundle: Bundle,
        locale: Locale
    ) -> [ResolvedSegment] {
        guard hasFormatting else {
            return [.attributedString(AttributedString(
                localized: String.LocalizationValue(key),
                table: table,
                bundle: bundle,
                locale: locale
            ))]
        }

        let localizationValue = foundationLocalizationValue()
        var options = AttributedString.LocalizationOptions()
        options.replacements = arguments.map(\.replacement)
        options.applyReplacementIndexAttribute = true
        let resolved = AttributedString(
            localized: localizationValue,
            options: options,
            table: table,
            bundle: bundle,
            locale: locale
        )

        var segments: [ResolvedSegment] = []
        for run in resolved.runs {
            let replacementIndex = run.replacementIndex.map { $0 - 1 }
            if let replacementIndex,
               arguments.indices.contains(replacementIndex) {
                switch arguments[replacementIndex].storage {
                case let .text(text, _):
                    segments.append(.text(text))
                    continue
                case let .attributedString(value):
                    append(value, to: &segments)
                    continue
                case let .localizedStringResource(resource):
                    append(AttributedString(localized: resource), to: &segments)
                    continue
                case .value:
                    break
                }
            }
            append(AttributedString(resolved[run.range]), to: &segments)
        }
        return segments
    }

    private func foundationLocalizationValue() -> String.LocalizationValue {
        var interpolation = String.LocalizationValue.StringInterpolation(
            literalCapacity: key.count,
            interpolationCount: arguments.count
        )
        var literalStart = key.startIndex
        var cursor = key.startIndex
        var argumentIndex = 0

        while cursor < key.endIndex, argumentIndex < arguments.count {
            guard key[cursor] == "%" else {
                cursor = key.index(after: cursor)
                continue
            }

            let next = key.index(after: cursor)
            guard next < key.endIndex else { break }
            if key[next] == "%" {
                cursor = key.index(after: next)
                continue
            }

            guard let specifierEnd = formatSpecifierEnd(startingAt: cursor) else {
                cursor = next
                continue
            }
            let literal = unescapedLiteral(String(key[literalStart..<cursor]))
            interpolation.appendLiteral(literal)
            let specifier = String(key[cursor...specifierEnd])
            interpolation.appendInterpolation(
                placeholder: placeholder(for: specifier),
                specifier: specifier
            )
            argumentIndex += 1
            cursor = key.index(after: specifierEnd)
            literalStart = cursor
        }

        interpolation.appendLiteral(unescapedLiteral(String(key[literalStart...])))
        return String.LocalizationValue(stringInterpolation: interpolation)
    }

    private func formatSpecifierEnd(startingAt start: String.Index) -> String.Index? {
        let conversions = "diouxXfFeEgGaAcCsSp@"
        var cursor = key.index(after: start)
        while cursor < key.endIndex {
            if conversions.contains(key[cursor]) {
                return cursor
            }
            cursor = key.index(after: cursor)
        }
        return nil
    }

    private func placeholder(
        for specifier: String
    ) -> String.LocalizationValue.Placeholder {
        guard let conversion = specifier.last else { return .object }
        switch conversion {
        case "d", "i", "c":
            return .int
        case "o", "u", "x", "X":
            return .uint
        case "f", "F", "e", "E", "g", "G", "a", "A":
            return specifier.contains("l") ? .double : .float
        default:
            return .object
        }
    }

    private func unescapedLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "%%", with: "%")
    }

    private func append(
        _ value: AttributedString,
        to segments: inout [ResolvedSegment]
    ) {
        guard !value.characters.isEmpty else { return }
        if case let .attributedString(previous)? = segments.last {
            var combined = previous
            combined.append(value)
            segments[segments.count - 1] = .attributedString(combined)
        } else {
            segments.append(.attributedString(value))
        }
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var key: String
        fileprivate var arguments: [FormatArgument]
        fileprivate var seed: UniqueSeedGenerator

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.key = String()
            self.key.reserveCapacity(literalCapacity + interpolationCount * 2)
            self.arguments = []
            self.arguments.reserveCapacity(interpolationCount)
            self.seed = UniqueSeedGenerator()
        }

        public mutating func appendLiteral(_ literal: String) {
            key.append(literal.replacingOccurrences(of: "%", with: "%%"))
        }

        public mutating func appendInterpolation(_ string: String) {
            appendValue(string, specifier: "%@")
        }

        public mutating func appendInterpolation(_ substring: Substring) {
            appendInterpolation(String(substring))
        }

        public mutating func appendInterpolation<Subject>(
            _ subject: Subject,
            formatter: Formatter? = nil
        ) where Subject: ReferenceConvertible {
            appendValue(subject._bridgeToObjectiveC() as! NSObject, formatter: formatter)
        }

        public mutating func appendInterpolation<Subject>(
            _ subject: Subject,
            formatter: Formatter? = nil
        ) where Subject: NSObject {
            appendValue(subject, formatter: formatter)
        }

        public mutating func appendInterpolation<T>(_ value: T)
        where T: _FormatSpecifiable {
            appendValue(value._arg, specifier: value._specifier)
        }

        public mutating func appendInterpolation<T>(_ value: T, specifier: String)
        where T: _FormatSpecifiable {
            appendValue(value._arg, specifier: specifier)
        }

        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F)
        where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == String {
            appendText(Text(input, format: format))
        }

        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F)
        where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == AttributedString {
            appendText(Text(input, format: format))
        }

        public mutating func appendInterpolation(_ text: Text) {
            appendText(text)
        }

        public mutating func appendInterpolation(_ image: Image) {
            appendText(Text(image))
        }

        public mutating func appendInterpolation(_ attributedString: AttributedString) {
            key.append("%@")
            arguments.append(FormatArgument(storage: .attributedString(attributedString)))
        }

        public mutating func appendInterpolation(_ attributedSubstring: AttributedSubstring) {
            appendInterpolation(AttributedString(attributedSubstring))
        }

        public mutating func appendInterpolation(_ resource: LocalizedStringResource) {
            key.append("%@")
            arguments.append(FormatArgument(storage: .localizedStringResource(resource)))
        }

        public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) {
            appendText(Text(date, style: style))
        }

        public mutating func appendInterpolation(_ dates: ClosedRange<Date>) {
            appendText(Text(dates))
        }

        public mutating func appendInterpolation(_ interval: DateInterval) {
            appendText(Text(interval))
        }

        public mutating func appendInterpolation(
            timerInterval: ClosedRange<Date>,
            pauseTime: Date? = nil,
            countsDown: Bool = true,
            showsHours: Bool = true
        ) {
            appendText(Text(
                timerInterval: timerInterval,
                pauseTime: pauseTime,
                countsDown: countsDown,
                showsHours: showsHours
            ))
        }

        @_disfavoredOverload
        public mutating func appendInterpolation<Value, Format>(
            _ source: TimeDataSource<Value>,
            format: Format
        ) where Value == Format.FormatInput,
                Format: DiscreteFormatStyle,
                Format.FormatOutput == String {
            appendText(Text(source, format: format))
        }

        public mutating func appendInterpolation<Value, Format>(
            _ source: TimeDataSource<Value>,
            format: Format
        ) where Value == Format.FormatInput,
                Format: DiscreteFormatStyle,
                Format.FormatOutput == AttributedString {
            appendText(Text(source, format: format))
        }

        @_disfavoredOverload
        public mutating func appendInterpolation<T>(_ object: T) {
            appendInterpolation(String(describing: object))
        }

        private mutating func appendValue<Argument: CVarArg>(
            _ argument: Argument,
            formatter: Formatter? = nil,
            specifier: String = "%@"
        ) {
            key.append(specifier)
            arguments.append(FormatArgument(
                storage: .value(LocalizationValueArgument(argument), formatter)
            ))
        }

        private mutating func appendText(_ text: Text) {
            key.append("%@")
            arguments.append(FormatArgument(
                storage: .text(text, FormatArgument.Token(id: seed.take()))
            ))
        }
    }
}

private final class LocalizationValueArgument: CVarArg {
    let value: any CVarArg

    init(_ value: any CVarArg) {
        self.value = value
    }

    var _cVarArgEncoding: [Int] {
        value._cVarArgEncoding
    }
}

private struct UniqueSeedGenerator {
    var nextID = 0

    mutating func take() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

private extension LocalizedStringKey.FormatArgument {
    var replacement: any CVarArg {
        switch storage {
        case let .value(argument, formatter):
            let value = (argument as? LocalizationValueArgument)?.value ?? argument
            guard let formatter else { return value }
            return formatter.string(for: value) ?? String(describing: value)
        case .text, .attributedString, .localizedStringResource:
            return "\u{FFFC}"
        }
    }
}

public protocol _FormatSpecifiable: Equatable {
    associatedtype _Arg: CVarArg
    var _arg: _Arg { get }
    var _specifier: String { get }
}

extension Int: _FormatSpecifiable {
    public var _specifier: String { "%lld" }
}

extension Int8: _FormatSpecifiable {
    public var _specifier: String { "%d" }
}

extension Int16: _FormatSpecifiable {
    public var _specifier: String { "%d" }
}

extension Int32: _FormatSpecifiable {
    public var _specifier: String { "%d" }
}

extension Int64: _FormatSpecifiable {
    public var _specifier: String { "%lld" }
}

extension UInt: _FormatSpecifiable {
    public var _specifier: String { "%llu" }
}

extension UInt8: _FormatSpecifiable {
    public var _specifier: String { "%u" }
}

extension UInt16: _FormatSpecifiable {
    public var _specifier: String { "%u" }
}

extension UInt32: _FormatSpecifiable {
    public var _specifier: String { "%u" }
}

extension UInt64: _FormatSpecifiable {
    public var _specifier: String { "%llu" }
}

extension Float: _FormatSpecifiable {
    public var _specifier: String { "%f" }
}

extension Double: _FormatSpecifiable {
    public var _specifier: String { "%lf" }
}

extension CGFloat: _FormatSpecifiable {
    public var _specifier: String { "%lf" }
}
