//
//  File: LocalizationCompatibility.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

#if !canImport(Darwin)

// MARK: - Foundation type names

/// These aliases expose only the Foundation names consumed by VUI. Their
/// underscored implementations remain separate so the reduced behavior can be
/// compiled and tested on platforms where Foundation already owns the names.
public typealias LocalizedStringResource = _LocalizedStringResource
public typealias InlinePresentationIntent = _InlinePresentationIntent

extension String {
    public typealias LocalizationValue = _StringLocalizationValue
}

extension AttributedString {
    public typealias LocalizationOptions = _AttributedStringLocalizationOptions
}

// MARK: - Localized resolution

extension AttributedString {
    public init(
        localized value: String.LocalizationValue,
        table: String? = nil,
        bundle: Bundle? = nil,
        locale: Locale? = nil
    ) {
        self = value.resolvedAttributedString(
            table: table,
            bundle: bundle ?? .main,
            locale: locale ?? .current
        )
    }

    public init(
        localized value: String.LocalizationValue,
        options: LocalizationOptions,
        table: String? = nil,
        bundle: Bundle? = nil,
        locale: Locale? = nil
    ) {
        self = value.resolvedAttributedString(
            replacements: options.replacements ?? [],
            applyReplacementIndexAttribute:
                options.applyReplacementIndexAttribute,
            table: table,
            bundle: bundle ?? .main,
            locale: locale ?? .current
        )
    }

    /// Resolves the reduced resource carrier with its stored localization
    /// value. Resource-specific table, bundle, and locale metadata are not
    /// represented by this compatibility slice.
    public init(localized resource: LocalizedStringResource) {
        self = resource.value.resolvedAttributedString()
    }
}

extension String {
    /// Resolves the reduced resource carrier with its stored localization
    /// value. Resource-specific table, bundle, and locale metadata are not
    /// represented by this compatibility slice.
    public init(localized resource: LocalizedStringResource) {
        self = resource.value.resolvedString()
    }
}

// MARK: - Attributed localization attributes

extension AttributeScopes {
    /// A narrow compatibility scope used only to make
    /// `run.inlinePresentationIntent` available to VUI text consumers.
    public var localizationCompatibility: LocalizationCompatibilityAttributes.Type {
        LocalizationCompatibilityAttributes.self
    }

    public struct LocalizationCompatibilityAttributes: AttributeScope {
        public let inlinePresentationIntent: _InlinePresentationIntentAttribute
    }
}

extension AttributeDynamicLookup {
    public subscript<T>(
        dynamicMember keyPath: KeyPath<
            AttributeScopes.LocalizationCompatibilityAttributes,
            T
        >
    ) -> T where T: AttributedStringKey {
        self[T.self]
    }
}

// MARK: - Numeric format arguments

/// Some Foundation ports do not provide the numeric `_arg` projections used
/// by the localization interpolation protocol. These widening conversions
/// match the argument types consumed by the current format specifiers.
extension Int {
    public var _arg: Int64 { Int64(self) }
}

extension Int8 {
    public var _arg: Int32 { Int32(self) }
}

extension Int16 {
    public var _arg: Int32 { Int32(self) }
}

extension Int32 {
    public var _arg: Int32 { self }
}

extension Int64 {
    public var _arg: Int64 { self }
}

extension UInt {
    public var _arg: UInt64 { UInt64(self) }
}

extension UInt8 {
    public var _arg: UInt32 { UInt32(self) }
}

extension UInt16 {
    public var _arg: UInt32 { UInt32(self) }
}

extension UInt32 {
    public var _arg: UInt32 { self }
}

extension UInt64 {
    public var _arg: UInt64 { self }
}

extension Float {
    public var _arg: Float { self }
}

extension Double {
    public var _arg: Double { self }
}

extension CGFloat {
    public var _arg: CGFloat { self }
}

#endif
