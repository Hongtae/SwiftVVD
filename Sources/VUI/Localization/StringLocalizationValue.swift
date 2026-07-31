//
//  File: StringLocalizationValue.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// A testable counterpart for the localization-value carrier missing from
/// some Foundation ports.
///
/// This reduced carrier preserves only the localization pattern consumed by
/// `LocalizedStringKey`. It does not perform lookup, replacement formatting,
/// inflection, or locale-sensitive resolution. The underscored type remains
/// available on every platform so its compatibility behavior can be tested on
/// Apple platforms; non-Darwin builds expose it as `String.LocalizationValue`.
public struct _StringLocalizationValue: Equatable, ExpressibleByStringInterpolation {
    let pattern: String

    public init(_ value: String) {
        self.pattern = value
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.pattern = stringInterpolation.pattern
    }

    /// Centralizes the temporary raw-pattern fallback so non-Darwin API
    /// shims and Apple-platform tests exercise the same implementation.
    func unresolvedString() -> String {
        pattern
    }

    /// Builds the attributed raw-pattern fallback without claiming localized
    /// lookup or replacement-index behavior.
    func unresolvedAttributedString() -> AttributedString {
        AttributedString(pattern)
    }

    public enum Placeholder: Codable, Hashable, Sendable {
        case int
        case uint
        case float
        case double
        case object
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var pattern: String

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.pattern = String()
            self.pattern.reserveCapacity(literalCapacity + interpolationCount * 2)
        }

        public mutating func appendLiteral(_ literal: String) {
            pattern.append(literal)
        }

        /// Records the placeholder spelling needed by the current
        /// `LocalizedStringKey` bridge. Replacement values are intentionally
        /// retained by `LocalizedStringKey`, not by this reduced carrier.
        public mutating func appendInterpolation(
            placeholder: Placeholder,
            specifier: String
        ) {
            pattern.append(specifier)
        }
    }
}
