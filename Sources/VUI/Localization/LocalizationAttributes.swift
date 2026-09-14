//
//  File: LocalizationAttributes.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// A testable counterpart for the inline presentation-intent option set
/// missing from some Foundation ports.
///
/// Only the flags consumed by text style transfer are exposed. Additional
/// Markdown presentation intents remain outside this compatibility slice.
public struct _InlinePresentationIntent: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let emphasized = Self(rawValue: 1 << 0)
    public static let stronglyEmphasized = Self(rawValue: 1 << 1)
    public static let code = Self(rawValue: 1 << 2)
    public static let strikethrough = Self(rawValue: 1 << 5)
}

/// Stores the compatibility presentation intent on attributed-string runs.
/// Its Foundation attribute name keeps values stable across the temporary
/// compatibility boundary.
public enum _InlinePresentationIntentAttribute: CodableAttributedStringKey {
    public typealias Value = _InlinePresentationIntent
    public static let name = "NSInlinePresentationIntent"
}
