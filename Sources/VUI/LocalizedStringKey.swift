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
    private var arguments: [FormatArgument]

    public init(_ value: String) {
        self.key = value
        self.arguments = []
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        let value = String.LocalizationValue(
            stringInterpolation: stringInterpolation.foundationInterpolation
        )
        self.key = stringInterpolation.key
        self.hasFormatting = !stringInterpolation.argumentComparisons.isEmpty

        if stringInterpolation.argumentComparisons.isEmpty {
            self.arguments = []
        } else {
            self.arguments = stringInterpolation.argumentComparisons.map { comparison in
                FormatArgument(storage: .value(value, comparison))
            }
        }
    }

    var foundationValue: String.LocalizationValue {
        arguments.first?.storage.foundationValue ?? String.LocalizationValue(key)
    }

    struct FormatArgument: Equatable {
        final class Identity {}

        struct AnyEquatable {
            var value: Any
            var isEqual: (Any) -> Bool

            init<Value: Equatable>(_ value: Value) {
                self.value = value
                self.isEqual = { other in
                    (other as? Value) == value
                }
            }

            func isEqual(to other: AnyEquatable) -> Bool {
                isEqual(other.value)
            }
        }

        enum Comparison {
            case identity(Identity)
            case equatable(AnyEquatable)

            static func == (lhs: Comparison, rhs: Comparison) -> Bool {
                switch (lhs, rhs) {
                case let (.identity(lhs), .identity(rhs)):
                    return lhs === rhs
                case let (.equatable(lhs), .equatable(rhs)):
                    return lhs.isEqual(to: rhs)
                default:
                    return false
                }
            }
        }

        enum Storage {
            case value(String.LocalizationValue, Comparison)

            var foundationValue: String.LocalizationValue {
                switch self {
                case let .value(value, _):
                    return value
                }
            }
        }

        var storage: Storage

        static func == (lhs: FormatArgument, rhs: FormatArgument) -> Bool {
            switch (lhs.storage, rhs.storage) {
            case let (.value(_, lhsComparison), .value(_, rhsComparison)):
                return lhsComparison == rhsComparison
            }
        }
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var foundationInterpolation: String.LocalizationValue.StringInterpolation
        fileprivate var key: String
        fileprivate var argumentComparisons: [FormatArgument.Comparison]

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.foundationInterpolation = .init(
                literalCapacity: literalCapacity,
                interpolationCount: interpolationCount
            )
            self.key = String()
            self.key.reserveCapacity(literalCapacity + interpolationCount * 2)
            self.argumentComparisons = []
            self.argumentComparisons.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            foundationInterpolation.appendLiteral(literal)
            key.append(literal)
        }

        public mutating func appendInterpolation(_ string: String) {
            foundationInterpolation.appendInterpolation(string)
            appendIdentityArgument(formatSpecifier: "%@")
        }

        public mutating func appendInterpolation(_ substring: Substring) {
            appendInterpolation(String(substring))
        }

        public mutating func appendInterpolation<Subject>(
            _ subject: Subject,
            formatter: Formatter? = nil
        ) where Subject: ReferenceConvertible {
            let object = subject._bridgeToObjectiveC()
            if let formatter, let formatted = formatter.string(for: object) {
                foundationInterpolation.appendInterpolation(formatted)
            } else {
                foundationInterpolation.appendInterpolation(object as! NSObject)
            }
            appendIdentityArgument(formatSpecifier: "%@")
        }

        public mutating func appendInterpolation<Subject>(
            _ subject: Subject,
            formatter: Formatter? = nil
        ) where Subject: NSObject {
            if let formatter, let formatted = formatter.string(for: subject) {
                foundationInterpolation.appendInterpolation(formatted)
            } else {
                foundationInterpolation.appendInterpolation(subject)
            }
            appendIdentityArgument(formatSpecifier: "%@")
        }

        public mutating func appendInterpolation<T>(_ value: T)
        where T: _FormatSpecifiable {
            appendFoundationArgument(value._arg, specifier: value._specifier)
            appendIdentityArgument(formatSpecifier: value._specifier)
        }

        public mutating func appendInterpolation<T>(_ value: T, specifier: String)
        where T: _FormatSpecifiable {
            appendFoundationArgument(value._arg, specifier: specifier)
            appendIdentityArgument(formatSpecifier: specifier)
        }

        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F)
        where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == String {
            let wrappedInput = LocalizationFormatInput(value: input)
            let wrappedFormat = LocalizationFormatStyle(base: format)
            foundationInterpolation.appendInterpolation(wrappedInput, format: wrappedFormat)
            appendEquatableArgument(
                LocalizationFormatArgument(input: input, format: format),
                formatSpecifier: "%@"
            )
        }

        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F)
        where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == AttributedString {
            let wrappedInput = LocalizationFormatInput(value: input)
            let wrappedFormat = LocalizationFormatStyle(base: format)
            foundationInterpolation.appendInterpolation(wrappedInput, format: wrappedFormat)
            appendEquatableArgument(
                LocalizationFormatArgument(input: input, format: format),
                formatSpecifier: "%@"
            )
        }

        public mutating func appendInterpolation(_ attributedString: AttributedString) {
            foundationInterpolation.appendInterpolation(attributedString)
            appendEquatableArgument(attributedString, formatSpecifier: "%@")
        }

        public mutating func appendInterpolation(_ attributedSubstring: AttributedSubstring) {
            appendInterpolation(AttributedString(attributedSubstring))
        }

        @_disfavoredOverload
        public mutating func appendInterpolation<T>(_ object: T) {
            appendInterpolation(String(describing: object))
        }

        private mutating func appendIdentityArgument(formatSpecifier: String) {
            key.append(formatSpecifier)
            argumentComparisons.append(.identity(FormatArgument.Identity()))
        }

        private mutating func appendEquatableArgument<Value: Equatable>(
            _ value: Value,
            formatSpecifier: String
        ) {
            key.append(formatSpecifier)
            argumentComparisons.append(.equatable(FormatArgument.AnyEquatable(value)))
        }

        private mutating func appendFoundationArgument<Argument: CVarArg>(
            _ argument: Argument,
            specifier: String
        ) {
            guard let argument = argument as? any Foundation._FormatSpecifiable else {
                foundationInterpolation.appendInterpolation(String(describing: argument))
                return
            }
            appendFoundationArgument(argument, specifier: specifier)
        }

        private mutating func appendFoundationArgument<Argument: Foundation._FormatSpecifiable>(
            _ argument: Argument,
            specifier: String
        ) {
            foundationInterpolation.appendInterpolation(argument, specifier: specifier)
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

private struct LocalizationFormatArgument<Input: Equatable, Style: Equatable>: Equatable {
    var input: Input
    var format: Style
}

private struct LocalizationFormatInput<Value: Equatable>: Equatable, @unchecked Sendable {
    var value: Value
}

private struct LocalizationFormatStyle<Base: FormatStyle>: FormatStyle, @unchecked Sendable
where Base.FormatInput: Equatable {
    typealias FormatInput = LocalizationFormatInput<Base.FormatInput>
    typealias FormatOutput = Base.FormatOutput

    var base: Base

    func format(_ value: LocalizationFormatInput<Base.FormatInput>) -> Base.FormatOutput {
        base.format(value.value)
    }

    func locale(_ locale: Locale) -> Self {
        Self(base: base.locale(locale))
    }
}
