//
//  File: FontWidth.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Font {
    public struct Width: Hashable, Sendable {
        public var value: CGFloat

        public static let compressed = Width(-0.3)
        public static let condensed = Width(-0.2)
        public static let standard = Width(0)
        public static let expanded = Width(0.2)

        public init(_ value: CGFloat) {
            self.value = value
        }
    }

    public func width(_ width: Width) -> Font {
        Font(provider: FontBox(ModifierProvider(base: self, modifier: WidthModifier(width: width.value))))
    }
}
