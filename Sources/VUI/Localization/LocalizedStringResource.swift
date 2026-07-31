//
//  File: LocalizedStringResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// A testable counterpart for the localized-resource carrier missing from
/// some Foundation ports.
///
/// The current VUI consumer only needs stable value storage and equality.
/// Table, bundle, comment, Codable, and full interpolation surfaces remain
/// intentionally absent until the cross-platform localization resolver is
/// implemented.
public struct _LocalizedStringResource: Equatable {
    let value: _StringLocalizationValue

    public init(_ value: String) {
        self.value = _StringLocalizationValue(value)
    }

    public init(_ value: _StringLocalizationValue) {
        self.value = value
    }
}
