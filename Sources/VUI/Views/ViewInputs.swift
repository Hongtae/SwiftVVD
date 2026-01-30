//
//  File: ViewInputs.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ViewInputs {
    var base: _GraphInputs
    var layouts: LayoutInputs = LayoutInputs()
    var preferences: PreferenceInputs = PreferenceInputs(preferences: [])
    var traits: ViewTraitKeys = ViewTraitKeys()

    var listInputs: _ViewListInputs {
        _ViewListInputs(base: self.base,
                        layouts: self.layouts,
                        preferences: self.preferences,
                        traits: self.traits)
    }

    static func inputs(with base: _GraphInputs) -> _ViewInputs {
        _ViewInputs(base: base,
                    layouts: LayoutInputs(),
                    preferences: PreferenceInputs(preferences: []),
                    traits: ViewTraitKeys())
    }
}

struct ViewTraitKeys {
    var types: Set<ObjectIdentifier> = []
}

struct ViewStyles {
    var foregroundStyle: (primary: AnyShapeStyle?,
                          secondary: AnyShapeStyle?,
                          tertiary: AnyShapeStyle?) = (nil, nil, nil)
}

protocol ViewStyleModifier: Equatable {
    var isResolved: Bool { get }
    func apply(to style: inout ViewStyles)
    mutating func resolve(containerView: ViewContext)
    mutating func reset()
}

extension ViewStyleModifier {
    func isEqual(to: any ViewStyleModifier) -> Bool {
        if let other = to as? Self {
            return self == other
        }
        return false
    }
}

public struct _ViewListInputs {
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static var none: Options { Options(rawValue: 0) }
    }

    var base: _GraphInputs
    var layouts: LayoutInputs = LayoutInputs()
    var preferences: PreferenceInputs = PreferenceInputs(preferences: [])
    var traits: ViewTraitKeys = ViewTraitKeys()
    var options: Options = .none

    var inputs: _ViewInputs {
        _ViewInputs(base: self.base,
                    layouts: self.layouts,
                    preferences: self.preferences,
                    traits: self.traits)
    }
}
