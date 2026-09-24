//
//  File: FontResolved.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Font {
    public struct Resolved: Hashable, Sendable {
        var font: Font
        var context: Context

        // Realization belongs to the shared request cache, independently of value copies.
        var resource: FontResource { font.platformFont(in: context) }

        public var isBold: Bool { resource.realizedTraits.symbolic & 2 != 0 }
        public var isItalic: Bool { resource.realizedTraits.symbolic & 1 != 0 }
        public var pointSize: CGFloat { resource.pointSize }
        public var weight: Weight { Weight(value: resource.realizedTraits.weight) }
        public var width: Width { Width(resource.realizedTraits.width) }
        public var leading: Leading { resource.stylePolicy?.leading ?? .standard }
        public var isMonospaced: Bool { resource.realizedTraits.isMonospaced }
        public var isLowercaseSmallCaps: Bool { hasLowercaseSmallCaps }
        public var isUppercaseSmallCaps: Bool { hasLowercaseSmallCaps }
        public var isSmallCaps: Bool { hasLowercaseSmallCaps }

        private var hasLowercaseSmallCaps: Bool {
            var descriptor = font.resolveDescriptor(in: context)
            for modifier in context.fontModifiers {
                modifier.modify(descriptor: &descriptor, in: context)
            }
            return descriptor.shapingFeatures.last {
                $0.tag == 0x736d_6370
            }.map { $0.value != 0 } ?? false
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.resource == rhs.resource
        }

        public func hash(into hasher: inout Hasher) {
            resource.hash(into: &hasher)
        }
    }

    public func resolve(in context: Context) -> Resolved {
        Resolved(font: self, context: context)
    }
}
