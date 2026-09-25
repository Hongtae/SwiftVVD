//
//  File: TextLayoutKey.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Text {
    public struct LayoutKey: PreferenceKey, Sendable {
        public struct AnchoredLayout: Equatable {
            public var origin: Anchor<CGPoint>
            public var layout: Layout

            public static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.origin == rhs.origin && lhs.layout == rhs.layout
            }
        }

        public typealias Value = [AnchoredLayout]
        public static var defaultValue: Value { [] }

        public static func reduce(value: inout Value, nextValue: () -> Value) {
            value.append(contentsOf: nextValue())
        }
    }
}

struct TextLayoutQuery: Rule, AsyncAttribute {
    var _resolvedText: Attribute<ResolvedStyledText>
    var _position: Attribute<CGPoint>
    var _size: Attribute<CGSize>
    var _transform: Attribute<ViewTransform>

    var value: Text.LayoutKey.Value {
        let size = _size.value
        guard let layout = _resolvedText.value.layoutValue(
            in: CGRect(origin: .zero, size: size), with: size, applyingMarginOffsets: false
        ) else { return [] }
        let geometry = AnchorGeometry(_position: _position, _size: _size, _transform: _transform)
        return [.init(origin: Anchor(anchor: UnitPoint.topLeading, geometry: geometry), layout: layout)]
    }
}
