//
//  File: FontStylisticAlternative.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

extension Font {
    /// Selects a stylistic set supplied by the font's shaping tables.
    public enum _StylisticAlternative: Int, Hashable {
        case one = 1
        case two
        case three
        case four
        case five
        case six
        case seven
        case eight
        case nine
        case ten
        case eleven
        case twelve
        case thirteen
        case fourteen
        case fifteen
        case sixteen
        case seventeen
        case eighteen
        case nineteen
        case twenty
    }

    public func _stylisticAlternative(_ alternative: _StylisticAlternative) -> Font {
        Font(provider: FontBox(ModifierProvider(base: self,
            modifier: StylisticAlternativeModifier(alternative: alternative))))
    }
}

@available(*, unavailable)
extension Font._StylisticAlternative: Sendable {}
