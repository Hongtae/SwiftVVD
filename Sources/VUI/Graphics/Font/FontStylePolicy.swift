//
//  File: FontStylePolicy.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Role-specific typography data, retained separately from the selected physical face.
struct FontStylePolicy: Hashable, Sendable {
    let style: Font.TextStyle
    private var symbolicTraits: UInt32 = 0

    init(style: Font.TextStyle) { self.style = style }

    var nominalSize: Double { Double(Font.pointSize(for: style)) }

    var leading: Font.Leading {
        if symbolicTraits & 0x10000 != 0 { return .loose }
        if symbolicTraits & 0x8000 != 0 { return .tight }
        return .standard
    }

    func applying(trait: UInt32, active: Bool) -> Self {
        var value = self
        if !active {
            value.symbolicTraits &= ~trait
        } else if trait != 0x10000 || (style != .subheadline && style != .footnote) {
            value.symbolicTraits |= trait
        }
        return value
    }

    var targetHeight: Double {
        let height: Double = switch style {
        case .largeTitle: 32
        case .title: 26
        case .title2: 22
        case .title3: 20
        case .headline, .body: 16
        case .callout: 15
        case .subheadline: 14
        case .footnote, .caption, .caption2: 13
        }
        switch leading {
        case .standard: return height
        case .tight: return height - 2
        case .loose: return height + 2
        }
    }

    func lineHeightRatio(languageGroup: Int) -> Double {
        guard languageGroup > 0 else { return 0 }
        guard languageGroup > 1 else { return 0.33 }
        let heights: (Double, Double, Double) = switch style {
        case .largeTitle: (34, 39, 43.75)
        case .title: (30, 33, 37)
        case .title2: (24, 27, 30.25)
        case .title3: (22, 24, 27)
        case .headline, .body: (18, 19, 21.25)
        case .callout: (17, 18, 20.25)
        case .subheadline: (16, 17, 19)
        case .footnote, .caption, .caption2: (15, 16, 18)
        }
        let height = languageGroup == 2 ? heights.0 : languageGroup == 3 ? heights.1 : heights.2
        return height / targetHeight
    }
}
