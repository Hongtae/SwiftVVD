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
/// This reduced carrier preserves the localization pattern and whether its
/// format specifiers came from interpolation, then routes that state through
/// the compatibility resolver. The underscored type remains available on
/// every platform so its behavior can be compared with Foundation on Apple
/// platforms; non-Darwin builds expose it as `String.LocalizationValue`.
public struct _StringLocalizationValue: Equatable, ExpressibleByStringInterpolation {
    let pattern: String
    /// Directly initialized percent spellings are literal; only interpolation
    /// records formatting placeholders.
    let hasFormatting: Bool

    public init(_ value: String) {
        self.pattern = value
        self.hasFormatting = false
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.pattern = stringInterpolation.pattern
        self.hasFormatting = stringInterpolation.hasFormatting
    }

    /// Resolves the stored key into the minimal run carrier shared by the
    /// non-Darwin text path and Darwin equivalence tests.
    func resolvedLocalization(
        replacements: [any CVarArg] = [],
        applyReplacementIndexAttribute: Bool = false,
        table: String? = nil,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> LocalizationResolver.Result {
        let localizedPattern = LocalizationResolver.localizedPattern(
            forKey: pattern,
            table: table,
            bundle: bundle,
            locale: locale,
            replacements: hasFormatting ? replacements : []
        )
        return LocalizationResolver.resolve(
            pattern: localizedPattern,
            replacements: hasFormatting ? replacements : [],
            locale: locale,
            applyReplacementIndexAttribute: applyReplacementIndexAttribute
        )
    }

    /// Materializes the compatibility AttributedString initializer result.
    /// Internal localized Text resolution consumes `resolvedLocalization`
    /// directly and does not enumerate Foundation attributed runs.
    func resolvedAttributedString(
        replacements: [any CVarArg] = [],
        applyReplacementIndexAttribute: Bool = false,
        table: String? = nil,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> AttributedString {
        resolvedLocalization(
            replacements: replacements,
            applyReplacementIndexAttribute: applyReplacementIndexAttribute,
            table: table,
            bundle: bundle,
            locale: locale
        ).attributedString()
    }

    /// Resolves the plain string view of the attributed result.
    func resolvedString(
        replacements: [any CVarArg] = [],
        table: String? = nil,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        resolvedLocalization(
            replacements: replacements,
            table: table,
            bundle: bundle,
            locale: locale
        ).string
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
        var hasFormatting: Bool

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.pattern = String()
            self.pattern.reserveCapacity(literalCapacity + interpolationCount * 2)
            self.hasFormatting = false
        }

        public mutating func appendLiteral(_ literal: String) {
            // Literal percent signs must remain distinguishable from the
            // format specifiers appended for interpolation arguments.
            pattern.append(literal.replacingOccurrences(of: "%", with: "%%"))
        }

        /// Records the placeholder spelling needed by the current
        /// `LocalizedStringKey` bridge. Replacement values are intentionally
        /// retained by `LocalizedStringKey`, not by this reduced carrier.
        public mutating func appendInterpolation(
            placeholder: Placeholder,
            specifier: String
        ) {
            pattern.append(specifier)
            hasFormatting = true
        }
    }
}
