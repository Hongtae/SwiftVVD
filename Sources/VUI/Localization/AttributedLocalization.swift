//
//  File: AttributedLocalization.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// The subset of attributed-localization options consumed by
/// `LocalizedStringKey`.
///
/// This testable counterpart records replacement inputs and the request for
/// replacement-index attributes. The non-Darwin compatibility initializer
/// forwards both members to the shared resolver.
public struct _AttributedStringLocalizationOptions {
    public var replacements: [any CVarArg]?
    public var applyReplacementIndexAttribute: Bool

    public init() {
        self.replacements = nil
        self.applyReplacementIndexAttribute = false
    }
}
